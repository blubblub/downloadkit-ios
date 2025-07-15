//
//  WebDownloadProcessor.swift
//  DownloadKit
//
//  Created by Dal Rupnik on 10/30/20.
//

import Foundation
import os.log

extension URLSessionConfiguration {
    var isEphemeral: Bool {
        let config = self
        return config.urlCache == nil &&
               config.httpCookieStorage == nil &&
               config.urlCredentialStorage == nil
    }
}

// WebDownloadProcessor now uses the centralized DownloadKitError system

/// Wrapper for NSURLSession delegate, between DownloadQueue and Downloadable,
/// so we can correctly track.
public actor WebDownloadProcessor: NSObject, DownloadProcessor {

    // MARK: - Private Properties
    
    /// URLSession that does everything. Using force unwrap here, so we can initialize it in constructor
    /// dynamically.
    private var session: URLSession!
    
    /// Holds properties to current items for quick access.
    private var downloadables = Array<WebDownload>()
    
    // MARK: - Public Properties
    
    public weak var observer: DownloadProcessorObserver?
    
    private let log = Logger.logWebDownloadProcessor
    
    public var isActive = true
    
    // MARK: - Initialization
    
    public init(identifier: String = "org.blubblub.downloadkit.websession") {
        let sessionConfiguration = URLSessionConfiguration.background(withIdentifier: identifier)
        
        sessionConfiguration.waitsForConnectivity = true
        sessionConfiguration.allowsConstrainedNetworkAccess = true
        sessionConfiguration.allowsCellularAccess = true
        
        self.init(configuration: sessionConfiguration)
    }
    
    public init(configuration: URLSessionConfiguration) {
        super.init()
        
        // For all sessions, we need to set ourselves as the delegate
        // This enables proper handling of delegate callbacks and routing to WebDownload instances
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        
    }
    
    // MARK: - DownloadProcessor
    public func set(observer: (any DownloadProcessorObserver)?) {
        self.observer = observer
    }
    
    public func canProcess(downloadable: Downloadable) -> Bool {
        return downloadable is WebDownload && isActive
    }
    
    public func process(_ downloadable: Downloadable) async {
        guard let webDownload = downloadable as? WebDownload else {
            let error = "Cannot process the unsupported download type. Item: \(downloadable)"
            await observer?.downloadDidError(self,
                                       downloadable: downloadable,
                                       error: DownloadKitError.processor(.cannotProcess(error)))
            return
        }
        
        // we're already processing item with the same identifier
        let webDownloadIdentifier = await webDownload.identifier
        
        guard await self.downloadable(for: webDownloadIdentifier) == nil else {
            return
        }
        
        await prepare(downloadable: webDownload)
        
        await webDownload.start(with: [DownloadParameter.urlSession: session])
        
        self.downloadables.append(webDownload)
        
        await self.observer?.downloadDidBegin(self, downloadable: webDownload)
    }
    
    public func pause() async {
        isActive = false
        for task in downloadables {
            await task.pause()
        }
    }
    
    public func resume() async {
        isActive = true
        for downloadable in downloadables {
            await downloadable.start(with: [DownloadParameter.urlSession: session])
        }
    }
    
    public func enqueuePending() async {
        let (_, _, downloadTasks) = await session.tasks
        
        for task in downloadTasks {
            let item: WebDownload?
            
            if let downloadItem = await self.downloadable(for: task) {
                item = downloadItem
            } else {
                item = WebDownload(task: task)
                await prepare(downloadable: item!)
            }
            
            // If we were unable to decode the item from task completion,
            // it is likely a task that we did not start. We shouldn't handle it.
            if let item = item {
                self.downloadables.append(item)
                
                await self.observer?.downloadDidBegin(self, downloadable: item)
            }
        }
    }
    
    private func prepare(downloadable: WebDownload) async {
        await downloadable.addCompletion { result in
            Task {
                switch result {
                case .failure(let error):
                    await self.observer?.downloadDidError(self, downloadable: downloadable, error: error)
                case .success(let url):
                    await self.observer?.downloadDidFinishTransfer(self, downloadable: downloadable, to: url)
                }
                
                // Clean up completed download from our tracking array
                await self.remove(downloadable: downloadable)
            }
        }
        
        await downloadable.addProgressUpdate { totalBytesWritten, totalSize in
            Task {
                // Ensure there was at least some progress written.
                if totalBytesWritten > 0 && totalSize == 0 {
                    await self.observer?.downloadDidStartTransfer(self, downloadable: downloadable)
                }
                
                await self.observer?.downloadDidTransferData(self, downloadable: downloadable)
            }
        }
    }
    
    private func remove(downloadable: WebDownload) {
        self.downloadables.removeAll { $0 === downloadable }
    }
    
    private func downloadable(for identifier: String) async -> WebDownload? {
        for item in downloadables {
            let itemIdentifier = await item.identifier
            if itemIdentifier == identifier {
                return item
            }
        }
        
        return nil
    }
    
    private func downloadable(for task: URLSessionTask) async -> WebDownload? {
        for item in downloadables {
            let itemIdentifier = await item.task?.taskIdentifier
            if itemIdentifier == task.taskIdentifier {
                return item
            }
        }
        
        return nil
    }
}

// MARK: - URLSessionDelegate
extension WebDownloadProcessor : URLSessionDownloadDelegate {
    nonisolated public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        log.info("URLSession delegate: didFinishDownloadingTo called for task \(downloadTask.taskIdentifier)")
        
        // We have to move file here, otherwise file is gone before Task is executed.
        let tempLocation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-download.tmp")
        
        do {
            try FileManager.default.moveItem(at: location, to: tempLocation)
            log.info("Successfully moved file to \(tempLocation)")
            
            Task {
                guard let downloadable = await self.downloadable(for: downloadTask) else {
                    log.error("DidFinishDownloadingTo: Could not find downloadable for download task \(downloadTask.taskIdentifier)")
                    return
                }
                
                let downloadableId = await downloadable.identifier
                log.info("Forwarding didFinishDownloadingTo to downloadable \(downloadableId)")
                // Forward the call to the downloadable item
                downloadable.urlSession(session, downloadTask: downloadTask, didFinishDownloadingTo: tempLocation)
            }
        }
        catch let error {
            Task {
                guard let downloadable = await self.downloadable(for: downloadTask) else {
                    log.error("Move file error. DidFinishDownloadingTo: Could not find downloadable for download task \(downloadTask.taskIdentifier) \(error)")
                    return
                }
                
                await downloadable.completeDownload(url: nil, error: error)
            }
        }
    }
        
    nonisolated public func urlSession(_ session: Foundation.URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task {
            guard let downloadable = await self.downloadable(for: downloadTask) else {
                log.error("DidFinishDownloadingTo: Could not find downloadable for download task \(downloadTask)")
                return
            }
            
            downloadable.urlSession(session, downloadTask: downloadTask, didWriteData: bytesWritten, totalBytesWritten: totalBytesWritten, totalBytesExpectedToWrite: totalBytesExpectedToWrite)
        }
    }
    
    nonisolated public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        Task {
            // Go through all downloadables
            for downloadable in await self.downloadables {
                downloadable.urlSession(session, didBecomeInvalidWithError: error)
            }
        }
    }
    
    nonisolated public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task {
            guard let error = error else {
                return
            }
            
            guard let downloadable = await self.downloadable(for: task) else {
                log.error("didCompleteWithError: Could not find downloadable for download task \(task)")
                return
            }
            
            downloadable.urlSession(session, task: task, didCompleteWithError: error)
        }
    }
    
    
    /// Called when all background tasks have been completed
    /// This is crucial for background app refresh and proper session lifecycle management
    nonisolated public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task {
            // TODO: Not sure what to do here?
        }
    }
}

// MARK: - Convenience Extensions

public extension WebDownloadProcessor {
    static func priorityProcessor(with priorityConfiguration: URLSessionConfiguration = URLSessionConfiguration.background(withIdentifier: "org.blubblub.downloadkit.session.priority")) -> WebDownloadProcessor {
        priorityConfiguration.allowsCellularAccess = true

        priorityConfiguration.allowsExpensiveNetworkAccess = true
        priorityConfiguration.allowsConstrainedNetworkAccess = true

        priorityConfiguration.waitsForConnectivity = true
        
        return WebDownloadProcessor(configuration: priorityConfiguration)
    }
}
