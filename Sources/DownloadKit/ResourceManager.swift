//
//  AssetManager.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 05/10/2017.
//  Copyright © 2017 Blub Blub. All rights reserved.
//

import Foundation
import RealmSwift
import os.log

public protocol ResourceManagerObserver: AnyObject {
    // Called when certain download starts downloading
    func didStartDownloading(_ download: DownloadRequest)
    
    // Called when download is finished. The file is already downloaded.
    func didFinishDownloading(_ download: DownloadRequest)
    
    // Called when file fails to download, but will no longer retry, as internal logic had completed.
    func didFailToDownload(_ download: DownloadRequest, with error: Error)
    
    // Called when file download fails, but will still retry again with provided request.
    func willRetryFailedDownload(_ download: DownloadRequest, originalDownload: DownloadRequest, with error: Error)
}

/// Optional observer parameters
public extension ResourceManagerObserver {
    func didStartDownloading(_ download: DownloadRequest) {
        
    }
    
    func willRetryFailedDownload(_ download: DownloadRequest, originalDownload: DownloadRequest, with error: Error) {
        
    }
}

/// Completion block, having success flag and item identifier
public typealias ProgressCompletion = (Bool, String) -> Void

public enum DownloadPriority {
    case normal
    case high
}

public enum StoragePriority: String {
    /// Cache Manager should permanently store the file. This should be used for offline mode.
    case permanent
    
    /// Cache Manager should place the file in temporary folder. Once system clears the folder
    /// due to space constraints, it will have to be redownloaded.
    case cached
}

public struct RequestOptions {
    public var downloadPriority: DownloadPriority = .normal
    public var storagePriority: StoragePriority = .cached
    
    public init(downloadPriority: DownloadPriority = .normal,
                storagePriority: StoragePriority = .cached) {
        self.downloadPriority = downloadPriority
        self.storagePriority = storagePriority
    }
}


/// Public API for Asset Manager. Combines all the smaller pieces of the API.
/// Generally you should only use this API, aside from setting up the system.
/// Default implementation uses:
///  - 1 Priority Queue (with priority Web Processor) and 1 normal queue (with normal Web Processor).
///  - Weighted Mirror Policy (going from Mirror to Mirror, before retrying last one 3 times).
public class ResourceManager {
    
    private struct Observer {
        private(set) weak var instance: ResourceManagerObserver?
    }
    
    // MARK: - Private Properties
    
    private var assetCompletions: [String: [ProgressCompletion]] = [:]
    
    private let processQueue = DispatchQueue(label: "downloadkit.asset-manager.process-queue",
                                             qos: .background)

    private let observersQueue = DispatchQueue(label: "downloadkit.asset-manager.observers-queue",
                                               qos: .background)
    
    private var observers: [ObjectIdentifier: Observer] = [:]

    // MARK: - Public Properties
    public var log: OSLog = logDK
        
    public let downloadQueue: DownloadQueue
    public let priorityQueue: DownloadQueue?
    
    private var queues: [DownloadQueue] {
        return [priorityQueue, downloadQueue].compactMap { $0 }
    }
    
    public let cache: AssetCacheable
    
    public let progress = ResourceDownloadProgress()
    
    public private(set) var metrics = ResourceManagerMetrics()
    
    public convenience init(cache: AssetCacheable) {
        let downloadQueue = DownloadQueue()
        downloadQueue.add(processor: WebDownloadProcessor())
        
        let priorityQueue = DownloadQueue()
        priorityQueue.add(processor: WebDownloadProcessor.priorityProcessor())
        priorityQueue.simultaneousDownloads = 30
        
        self.init(cache: cache, downloadQueue: downloadQueue, priorityQueue: priorityQueue)
    }
    
    /// Designated initializer for AssetManager.
    /// - Parameters:
    ///   - cache: Cache Manager to use
    ///   - downloadQueue: Normal Download Queue
    ///   - priorityQueue: Priority Download Queue (to quickly download)
    public init(cache: AssetCacheable, downloadQueue: DownloadQueue, priorityQueue: DownloadQueue? = nil) {
        self.cache = cache
        self.downloadQueue = downloadQueue
        self.priorityQueue = priorityQueue
        
        downloadQueue.delegate = self
        priorityQueue?.delegate = self
    }
    
    @discardableResult
    public func request(resources: [ResourceFile]) -> [DownloadRequest] {
        return request(resources: resources, options: RequestOptions())
    }
    
    @discardableResult
    public func request(resources: [ResourceFile], options: RequestOptions) -> [DownloadRequest] {
        
        let uniqueAssets = resources.unique(\.id)
        
        // Grab Assets we need from file manager, filtering out those that are already downloaded.
        let downloads = cache.requestDownloads(assets: uniqueAssets, options: options)
        
        metrics.requested += uniqueAssets.count
                
        log.info("Requested unique asset count: \(uniqueAssets.count) Downloads: \(downloads.count)")
                
        guard downloads.count > 0 else {
            log.info("[AssetManager]: Metrics on no downloads: \(metrics.description)")
            return []
        }
        
        // We need to filter the downloads that are in progress, since there's not much we will do
        // in that case. For those that are in queue, we might move them to a higher priority queue.
        let finalDownloads = downloads.filter { !isDownloading(for: $0.downloadableIdentifier) }
        
        if downloads.count != finalDownloads.count {
            log.error("[AssetManager]: Final downloads mismatch: \(downloads.count) \(finalDownloads.count)")
        }
        
        if let priorityQueue = priorityQueue, options.downloadPriority == .high {
            // Move current priority queued downloads back to normal queue, because we have
            // a higher priority downloads now.
            let currentPriorityDownloads = priorityQueue.queuedDownloads
            priorityQueue.cancel(items: currentPriorityDownloads)
            
            let maxDownloadPriority = downloadQueue.currentMaximumPriority + 1
            
            for var currentPriorityDownload in currentPriorityDownloads {
                currentPriorityDownload.priority = maxDownloadPriority
            }
            
            metrics.priorityIncreased += finalDownloads.count
            metrics.priorityDecreased += currentPriorityDownloads.count
            
            downloadQueue.download(currentPriorityDownloads)
            
            priorityQueue.download(finalDownloads.map(\.mirror.downloadable))
            
            // If those downloads are on download queue and were now moved to priority,
            // we need to cancel them on download, so we do not download them twice.
            let normalQueuedDownloads = finalDownloads.filter { downloadQueue.hasItem(with: $0.downloadableIdentifier) }
            
            downloadQueue.cancel(items: normalQueuedDownloads.map(\.mirror.downloadable))
            
            log.info("Reprioritising assets: \(finalDownloads.map({ $0.downloadableIdentifier }).joined(separator: ", "))")
        }
        else {
            downloadQueue.download(finalDownloads.map(\.mirror.downloadable))
        }
        
        // Add downloads to monitor progresses.
        progress.add(downloadItems: finalDownloads.map(\.mirror.downloadable))
        
        log.info("[AssetManager]: Metrics on request: \(metrics.description)")
        
        return downloads
    }
    
    public func resume(completion: (() -> Void)? = nil) {
        isActive = true
        
        let completionCounter = priorityQueue != nil ? 2 : 1
        var currentCompletionCounter = 0
        
        downloadQueue.enqueuePending(completion: {
            currentCompletionCounter += 1
            
            if currentCompletionCounter >= completionCounter {
                completion?()
            }
        })
        
        priorityQueue?.enqueuePending(completion: {
            currentCompletionCounter += 1
            
            if currentCompletionCounter >= completionCounter {
                completion?()
            }
        })
    }
    
    public func cancelAll() {
        queues.forEach { $0.cancelAll() }
        
        for (identifier, completions) in assetCompletions {
            for completion in completions {
                completion(false, identifier)
            }
        }
        
        assetCompletions.removeAll()
    }
    
    public func add(observer: ResourceManagerObserver) {
        observersQueue.sync {
            self.observers[ObjectIdentifier(observer)] = Observer(instance: observer)
        }
    }
    
    public func remove(observer: ResourceManagerObserver) {
        observersQueue.sync {
            self.observers[ObjectIdentifier(observer)] = nil
        }
    }
    
    private func foreachObserver(action: (ResourceManagerObserver) -> Void) {
        observers.forEach { $0.value.instance.flatMap(action) }
        
        // cleanup deallocated observer wrappers
        for key in observers.compactMap({ $1.instance == nil ? $0 : nil }) {
            observers[key] = nil
        }
    }
}

// MARK: - DownloadQueueDelegate

extension ResourceManager: DownloadQueueDelegate {
    
    public func downloadQueue(_ queue: DownloadQueue, downloadDidStart item: Downloadable, with processor: DownloadProcessor) {
        guard let downloadRequest = cache.downloadRequest(for: item) else {
            return
        }
        
        processQueue.async {
            self.metrics.downloadBegan += 1
        }
        
        self.foreachObserver { $0.didStartDownloading(downloadRequest) }
    }
    
    public func downloadQueue(_ queue: DownloadQueue, downloadDidTransferData item: Downloadable, using processor: DownloadProcessor) {
        
        self.metrics.updateDownloadSpeed(item: item)
    }
            
    public func downloadQueue(_ queue: DownloadQueue, downloadDidFinish item: Downloadable, to location: URL) {
        do {
            // Move the file to a temporary location, otherwise it gets removed by the system immediately after this function completes
            let tempLocation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-download.tmp")
            try FileManager.default.moveItem(at: location, to: tempLocation)
            
            // Store the file to the cache
            processQueue.async {
                autoreleasepool {
                    do {
                        if let downloadRequest = try self.cache.download(item, didFinishTo: tempLocation) {
                            self.metrics.downloadCompleted += 1
                            self.metrics.bytesTransferred += item.totalBytes
                            self.metrics.updateDownloadSpeed(item: item)
                            
                            self.completeProgress(downloadRequest, item: item, with: nil)
                            
                            self.log.info("[AssetManager]: Download finished: \(item.description)")
                            
                            self.log.info("[AssetManager]: Metrics on download finished: \(self.metrics.description)")
                        }
                    }
                    catch let error {
                        self.log.error("[AssetManager]: Error caching file: \(error.localizedDescription)")
                        self.downloadQueue(queue, downloadDidFail: item, with: error)
                    }
                }
                
            }
        } catch let error {
            log.error("[AssetManager]: Error moving temporary file: \(error.localizedDescription)")
            processQueue.async {
                // Ensure error is handled, download actually did fail.
                self.downloadQueue(queue, downloadDidFail: item, with: error)
            }
        }
    }
    
    // Called when download had failed for any reason, including sessions being invalidated.
    public func downloadQueue(_ queue: DownloadQueue, downloadDidFail item: Downloadable, with error: Error) {
        let retryRequest = self.cache.download(item, didFailWith: error)
        
        // Check if we should retry, cache will tell us based on it's internal mirror policy.
        // We cannot switch queues here, if it was put on lower priority, it should stay on lower priority.
        if let retryRequest = retryRequest, let retry = retryRequest.retryRequest, let downloadable = retryRequest.downloadable {
            metrics.retried += 1
            metrics.updateDownloadSpeed(item: item)
            
            // Put it on the same queue.
            observersQueue.async {
                self.foreachObserver { $0.willRetryFailedDownload(retry, originalDownload: retryRequest.originalRequest, with: error) }
            }
            
            log.error("[AssetManager]: Download failed, retrying: \(item.identifier) Error: \(error.localizedDescription)")
            
            queue.download(downloadable)
        } else if let originalRequest = retryRequest?.originalRequest {
            metrics.failed += 1
            
            log.error("[AssetManager]: Download failed, done: \(item.identifier) Error: \(error.localizedDescription)")
                
            self.completeProgress(originalRequest, item: item, with: error)
        }
        else {
            log.error("[AssetManager]: Download failed, unknown: \(item.identifier) Error: \(error.localizedDescription)")
        }
        
        log.info("[AssetManager]: Metrics on download failed: \(metrics.description)")
    }
    
    private func completeProgress(_ downloadRequest: DownloadRequest, item: Downloadable, with error: Error?) {
        if let completions = self.assetCompletions[downloadRequest.id] {
            for completion in completions {
                completion(error == nil, downloadRequest.id)
            }
            
            removeAssetCompletion(for: downloadRequest.id)
        }
        
        observersQueue.async {
            if let error = error {
                self.foreachObserver { $0.didFailToDownload(downloadRequest, with: error) }
            } else {
                self.foreachObserver { $0.didFinishDownloading(downloadRequest) }
            }
        }
        
        progress.complete(identifier: item.identifier, with: error)
    }
}

extension ResourceManager {
    public func addAssetCompletion(for identifier: String, with completion: @escaping ProgressCompletion) {
        // If this asset is not downloading at all, call the closure immediately!
        guard hasDownloadable(with: identifier) else {
            completion(false, identifier)
            return
        }
        
        var completionBlocks: [ProgressCompletion] = []
        
        // Check if array is made, append existing blocks
        if let existingBlocks = assetCompletions[identifier] {
            completionBlocks.append(contentsOf: existingBlocks)
        }
        
        completionBlocks.append(completion)
        
        assetCompletions[identifier] = completionBlocks
    }
    
    public func removeAssetCompletion(for identifier: String) {
        assetCompletions[identifier] = nil
    }
}

// MARK: - Convenience Methods to downloads

extension ResourceManager: DownloadQueuable {
    
    public var isActive: Bool {
        get {
            return queues.reduce(false, { $0 || $1.isActive })
        }
        set {
            downloadQueue.isActive = newValue
            priorityQueue?.isActive = newValue
        }
    }
    
    public var currentDownloadCount: Int {
        queues.reduce(0, { $0 + $1.currentDownloads.count })
    }
    
    public var queuedDownloadCount: Int {
        queues.reduce(0, { $0 + $1.queuedDownloads.count })
    }
    
    public var downloads: [Downloadable] {
        queues.flatMap(\.downloads)
    }
    
    public var currentDownloads: [Downloadable] {
        queues.flatMap(\.currentDownloads)
    }
    
    public var queuedDownloads: [Downloadable] {
        queues.flatMap(\.queuedDownloads)
    }
    
    public func hasDownloadable(with identifier: String) -> Bool {
        queues.contains(where: { $0.hasDownloadable(with: identifier) })
    }
    
    public func downloadable(for identifier: String) -> Downloadable? {
        queues.compactMap { $0.downloadable(for: identifier) }.first
    }
    
    public func isDownloading(for identifier: String) -> Bool {
        queues.contains(where: { $0.isDownloading(for: identifier) })
    }
}


extension FileManager {
    static var temporaryDirectoryPath: String {
        NSTemporaryDirectory()
    }

    static var temporaryDirectoryURL: URL {
        URL(fileURLWithPath: FileManager.temporaryDirectoryPath, isDirectory: true)
    }
}


extension Array {
    public func unique(_ by: ((Element) -> String)) -> Array {
        var seen: [String: Bool] = [:]
        
        return self.filter { seen.updateValue(true, forKey: by($0)) == nil }
    }
}
