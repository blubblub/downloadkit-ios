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

public extension WebDownloadProcessor {
    enum ProcessorError: Error {
        case cannotProcess(String)
    }
}

/// Wrapper for NSURLSession delegate, between DownloadQueue and Downloadable,
/// so we can correctly track.
public class WebDownloadProcessor: NSObject, DownloadProcessor {
    
    // MARK: - Private Properties
    
    /// URLSession that does the download.
    private var session: URLSession!
    
    /// Holds properties to current items for quick access.
    private var items = Set<WebDownloadItem>()
    private var downloadTasks = [URLSessionDownloadTask]()
    
    private lazy var queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .background
        queue.name = "org.blubblub.downloadkit.processor.web"
        
        return queue
    }()
    
    // MARK: - Public Properties
    
    public weak var delegate: DownloadProcessorDelegate?
    
    public var log = logDK
    
    public var isActive = true
    
    
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
        guard let webItem = item as? WebDownloadItem else {
            let error = "Cannot process the unsupported download type. Item: \(item.description)"
            delegate?.downloadDidError(self,
                                       item: item,
                                       error: ProcessorError.cannotProcess(error))
            return
        }
        
        queue.addOperation { [weak self] in
            guard let self = self else { return }
            
            // we're already processing item with the same identifier
            guard !self.items.contains(webItem) else {
                return
            }
            
            let task = self.createTask(for: webItem)
            webItem.start(with: [DownloadParameter.urlDownloadTask: task])
            
            self.downloadTasks.append(task)
            self.items.insert(webItem)
            
            self.delegate?.downloadDidBegin(self, item: webItem)
        }
    }
    
    public func pause() {
        isActive = false
        queue.addOperation { [downloadTasks] in
            for task in downloadTasks {
                task.suspend()
            }
        }
    }
    
    public func resume() {
        isActive = true
        queue.addOperation { [downloadTasks] in
            for task in downloadTasks {
                task.resume()
            }
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
                    self.items.insert(item)
                    self.downloadTasks.append(task)
                    
                    self.delegate?.downloadDidBegin(self, item: item)
                }
            }
            
            completion?()
        }
    }
    
    private func createTask(for item: WebDownloadItem) -> URLSessionDownloadTask {
        let task = session.downloadTask(with: URLRequest(url: item.url))
        
        if item.priority > 0 {
            task.priority = URLSessionDownloadTask.highPriority
        }
        
        if item.totalSize > 0 {
            task.countOfBytesClientExpectsToReceive = item.totalSize
        }
        
        task.taskDescription = String(data: try! WebDownloadItem.encoder.encode(item), encoding: .utf8)
        return task
    }
    
    private func item(for task: URLSessionTask) -> WebDownloadItem? {
        return items.first(where: { $0.task?.taskIdentifier == task.taskIdentifier })
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
        
        delegate?.downloadDidTransferData(self, item: item)
    }
    
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        // Invalidate and clean up all transfers
        for item in self.items {
            if let error = error {
                delegate?.downloadDidError(self, item: item, error: error)
            }
        }
        
        downloadTasks.removeAll()
        items.removeAll()
    }
    
    public func urlSession(_ session: Foundation.URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let item = self.item(for: downloadTask) else {
            os_log(.fault, log: log, "[WebDownloadProcessor]: Consistency Error: Item for download task not found.")
            return
        }
        
        delegate?.downloadDidFinishTransfer(self, item: item, to: location)
    }
    

    // MARK: - URLSessionTaskDelegate
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Will get this callback once the task is completed, so cleanup.
        downloadTasks.removeAll(where: { $0.taskIdentifier == task.taskIdentifier })
        
        if let item = self.item(for: task) {
            if let error = error {
                os_log(.debug, log: log, "[DownloadQueue] Failed downloading error: %@", error.localizedDescription)
                delegate?.downloadDidError(self, item: item, error: error)
            } else {
                delegate?.downloadDidFinish(self, item: item)
            }
            
            // Update states.
            items.remove(item)
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
