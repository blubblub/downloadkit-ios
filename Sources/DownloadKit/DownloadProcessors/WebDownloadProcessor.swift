//
//  WebDownloadProcessor.swift
//  DownloadKit
//
//  Created by Dal Rupnik on 10/30/20.
//

import Foundation
import os.log

extension WebDownloadItem {
    static let decoder = JSONDecoder()
    static let encoder = JSONEncoder()
}

/// Wrapper for NSURLSession delegate, between DownloadQueue and Downloadable,
/// so we can correctly track.
public class WebDownloadProcessor: NSObject, DownloadProcessor {
    /// URLSession that does the download.
    private var session: URLSession!
    
    /// Holds properties to current items for quick access.
    private var itemMap: [Int: WebDownloadItem] = [:]
    private var downloadTaskMap: [Int: URLSessionDownloadTask] = [:]
    
    private lazy var queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .background
        queue.name = "org.blubblub.downloadkit.processor.web"
        
        return queue
    }()
    
    // MARK: - Public Properties
    public weak var delegate: DownloadProcessorDelegate?
    
    public var log: OSLog = logDK
    
    public var isActive: Bool = true
    
    
    // MARK: - Initialization
    
    public init(identifier: String = "org.blubblub.downloadkit.websession") {
        super.init()
        
        let sessionConfiguration = URLSessionConfiguration.background(withIdentifier: identifier)
        
        // TURNED THIS ON EXPERIMENTALLY. TEST THOROUGHLY DOWNLOADING!
        sessionConfiguration.waitsForConnectivity = true
        
        if #available(iOS 13.0, *) {
            sessionConfiguration.allowsConstrainedNetworkAccess = true
        }
        
        self.session = URLSession(configuration: sessionConfiguration,
                                  delegate: self, delegateQueue: self.queue)
    }
    
    public init(configuration: URLSessionConfiguration) {
        super.init()
        self.session = URLSession(configuration: configuration,
                                  delegate: self, delegateQueue: self.queue)
    }
    
    // MARK: - DownloadProcessor
    
    public func canProcess(item: Downloadable) -> Bool {
        return item is WebDownloadItem && isActive
    }
    
    public func process(_ item: Downloadable) {
        let itemDescription = item.description
        
        guard let item = item as? WebDownloadItem else {
            fatalError("WebDownloadProcessor: Cannot process the unsupported download type. Item: \(itemDescription)")
        }
        
        guard let task = prepare(item: item) else {
            return
        }
        
        task.resume()
        
        self.downloadTaskMap[item.task!.taskIdentifier] = item.task!
        self.itemMap[item.task!.taskIdentifier] = item
        
        delegate?.downloadDidBegin(self, item: item)
    }
    
    public func pause() {
        // TODO: Handle inActive flag and state of download tasks
        for (_, task) in downloadTaskMap {
            task.suspend()
        }
    }
    
    public func resume() {
        // TODO: Handle inActive flag and state of download tasks. We might need to tell delegate that we paused the tasks. Not sure what happens if tasks are resumed when they aren't suspended.
        for (_, task) in downloadTaskMap {
            task.resume()
        }
    }
    
    public func enqueuePending(completion: (() -> Void)? = nil) {
        session.getTasksWithCompletionHandler { _, _, downloadTasks in
            for task in downloadTasks {
                let item: WebDownloadItem?
                
                if let downloadItem = self.item(for: task) {
                    item = downloadItem
                } else {
                    item = WebDownloadItem(task: task)
                }
                
                // If we were unable to decode the item from task completion,
                // it is likely a task that we did not start. We shouldn't handle it.
                if let item = item {
                    self.itemMap[task.taskIdentifier] = item
                    self.downloadTaskMap[task.taskIdentifier] = task
                    
                    self.delegate?.downloadDidBegin(self, item: item)
                }
            }
            
            if let completion = completion {
                completion()
            }
        }
    }
    
    private func prepare(item: WebDownloadItem) -> URLSessionDownloadTask? {
        
        let request = URLRequest(url: item.url)
        var task: URLSessionDownloadTask?
        
        if let currentTask = item.task, currentTask.state != .suspended {
            task = session.downloadTask(with: request)
        }
        
        if task == nil {
            task = session.downloadTask(with: request)
        }
        
        log.info("Starting download: %@ priority: %d", item.url.absoluteString, item.priority)
        
        if item.priority > 0 {
            task!.priority = URLSessionDownloadTask.highPriority
        }
        
        if item.totalSize > 0 {
            task!.countOfBytesClientExpectsToReceive = item.totalSize
        }
        
        
        // Want to crash here, if no task set up, need to crash, so we see where it went wrong.
        task!.taskDescription = String(data: try! WebDownloadItem.encoder.encode(item), encoding: .utf8)
        return task
    }
    
    
    private func item(for task: URLSessionTask) -> WebDownloadItem? {
        return itemMap[task.taskIdentifier]
    }
}


extension WebDownloadProcessor: URLSessionDownloadDelegate {
    
    #if os(iOS)
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        
    }
    #endif
    
    public func urlSession(_ session: Foundation.URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {

        guard let item = self.item(for: downloadTask) else {
            return
        }
        
        // Should send start transfer notification, if the progress does not exist, or the completed count is 0.
        let shouldSendStartTransferNotification = (item.progress?.completedUnitCount ?? 0) == 0
        
        // Forward the call to correct item, to correctly update progress.
        item.didWriteData(bytesWritten: bytesWritten, totalBytesWritten: totalBytesWritten, totalBytesExpectedToWrite: totalBytesExpectedToWrite)
        
        // Ensure there was at least some progress written.
        if totalBytesWritten > 0 && shouldSendStartTransferNotification {
            delegate?.downloadDidStartTransfer(self, item: item)
        }
    }
    
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        // Invalidate and clean up all transfers
        for item in self.itemMap.values {
            if let error = error {
                delegate?.downloadDidError(self, item: item, error: error)
            }
        }
        
        downloadTaskMap.removeAll()
        itemMap.removeAll()
    }
    
    public func urlSession(_ session: Foundation.URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let item = self.item(for: downloadTask) else {
            log.fault("[WebDownloadProcessor]: Consistency Error: Item for download task not found.")
            return
        }
        
        delegate?.downloadDidFinishTransfer(self, item: item, to: location)
    }
    

    // MARK: - URLSessionTaskDelegate
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Will get this callback once the task is completed, so cleanup.
        self.downloadTaskMap[task.taskIdentifier] = nil
        
        if let item = self.item(for: task) {
            // Update states.
            self.itemMap[task.taskIdentifier] = nil
            
            if let error = error {
                self.delegate?.downloadDidError(self, item: item, error: error)
            }
            else {
                self.delegate?.downloadDidFinish(self, item: item)
            }
        }
    }
}

// MARK: - Convenience Extensions

public extension WebDownloadProcessor {
    static func priorityProcessor() -> WebDownloadProcessor {
        let priorityConfiguration = URLSessionConfiguration.background(withIdentifier: "org.blubblub.downloadkit.session.priority")
        priorityConfiguration.allowsCellularAccess = true
        
        if #available(iOS 13.0, *) {
            priorityConfiguration.allowsExpensiveNetworkAccess = true
            priorityConfiguration.allowsConstrainedNetworkAccess = true
        }
        
        priorityConfiguration.waitsForConnectivity = true
        
        return WebDownloadProcessor(configuration: priorityConfiguration)
    }
}
