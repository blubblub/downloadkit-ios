//
//  WebDownloadProcessor.swift
//  DownloadKit
//
//  Created by Dal Rupnik on 10/30/20.
//

import Foundation
import os.log

public extension WebDownloadProcessor {
    enum ProcessorError: Error {
        case cannotProcess(String)
    }
}

/// Wrapper for NSURLSession delegate, between DownloadQueue and Downloadable,
/// so we can correctly track.
public actor WebDownloadProcessor: NSObject, DownloadProcessor {
    
    // MARK: - Private Properties
    
    /// URLSession that does the download.
    private let session: URLSession
    
    /// Holds properties to current items for quick access.
    private var downloadables = Array<WebDownloadItem>()
    
    // MARK: - Public Properties
    
    public weak var delegate: DownloadProcessorDelegate?
    
    private let log = logDK
    
    public var isActive = true
    
    // MARK: - Initialization
    
    public init(identifier: String = "org.blubblub.downloadkit.websession") {
        let sessionConfiguration = URLSessionConfiguration.background(withIdentifier: identifier)
        
        sessionConfiguration.waitsForConnectivity = true
        sessionConfiguration.allowsConstrainedNetworkAccess = true
        
        self.init(configuration: sessionConfiguration)
    }
    
    public init(configuration: URLSessionConfiguration) {
        self.session = URLSession(configuration: configuration)
    }
    
    // MARK: - DownloadProcessor
    
    public func canProcess(downloadable: Downloadable) -> Bool {
        return downloadable is WebDownloadItem && isActive
    }
    
    public func process(_ downloadable: Downloadable) async {
        guard let webItem = downloadable as? WebDownloadItem else {
            let error = "Cannot process the unsupported download type. Item: \(downloadable)"
            delegate?.downloadDidError(self,
                                       downloadable: downloadable,
                                       error: ProcessorError.cannotProcess(error))
            return
        }
        
        // we're already processing item with the same identifier
        let webItemIdentifier = await webItem.identifier
        
        guard await item(for: webItemIdentifier) == nil else {
            return
        }
        
        await webItem.start(with: [DownloadParameter.urlSession: session])
        
        self.downloadables.append(webItem)
        
        self.delegate?.downloadDidBegin(self, downloadable: webItem)
    }
    
    public func pause() async {
        for task in downloadables {
            await task.pause()
        }
    }
    
    public func resume() async {
        for downloadable in downloadables {
            await downloadable.start(with: [DownloadParameter.urlSession: session])
        }
    }
    
    public func enqueuePending() async {
        let (_, _, downloadTasks) = await session.tasks
        
        for task in downloadTasks {
            let item: WebDownloadItem?
            
            if let downloadItem = await self.item(for: task) {
                item = downloadItem
            } else {
                item = WebDownloadItem(task: task)
            }
            
            // If we were unable to decode the item from task completion,
            // it is likely a task that we did not start. We shouldn't handle it.
            if let item = item {
                self.downloadables.append(item)
                
                self.delegate?.downloadDidBegin(self, downloadable: item)
            }
        }
    }
    
    private func resume(downloadable: WebDownloadItem) async {
        
        await downloadable.addCompletion { result in
            Task {
                
                switch result {
                case .failure(let error):
                    // Remove
                    
                    await self.delegate?.downloadDidError(self, downloadable: downloadable, error: error)
                case .success(let url):
                    await self.delegate?.downloadDidFinishTransfer(self, downloadable: downloadable, to: url)
                }
            }
        }
        
        await downloadable.addProgressUpdate { totalBytesWritten, totalSize in
            Task {
                // Ensure there was at least some progress written.
                if totalBytesWritten > 0 && totalSize == 0 {
                    await self.delegate?.downloadDidStartTransfer(self, downloadable: downloadable)
                }
                
                await self.delegate?.downloadDidTransferData(self, downloadable: downloadable)
            }
        }
    }
    
    private func remove(downloadable: WebDownloadItem) {
        self.downloadables.removeAll { $0 === downloadable }
    }
    
    private func item(for identifier: String) async -> WebDownloadItem? {
        for item in downloadables {
            let itemIdentifier = await item.identifier
            if itemIdentifier == identifier {
                return item
            }
        }
        
        return nil
    }
    
    private func item(for task: URLSessionTask) async -> WebDownloadItem? {
        for item in downloadables {
            let itemIdentifier = await item.task?.taskIdentifier
            if itemIdentifier == task.taskIdentifier {
                return item
            }
        }
        
        return nil
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
