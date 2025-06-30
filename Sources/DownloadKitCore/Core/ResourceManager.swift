//
//  ResourceManager.swift
//  DownloadKit
//
//  Created by Dal Rupnik on 2/5/21.
//

import Foundation
import os

public protocol ResourceManagerObserver: AnyObject {
    func didStartDownloading(_ downloadRequest: DownloadRequest)
    func willRetryFailedDownload(_ retryRequest: DownloadRequest, originalDownload: DownloadRequest, with error: Error)
}

/// ResourceManager manages a set of resources, allowing a user to request downloads from multiple mirrors,
/// managing caching and retries internally.
public actor ResourceManager: DownloadQueuable {
    
    // MARK: - Private Properties
    
    /// Queue for downloading resources.
    private let downloadQueue: DownloadQueue
    
    /// Priority queue for high priority downloads.
    private let priorityQueue: DownloadQueue?
    
    /// Cache where resource files are stored.
    public let cache: any ResourceCachable
    
    /// Progress tracker for all resource downloads.
    private let progress = ResourceDownloadProgress()
    
    private let log: Logger = logDK
    
    /// Metrics for resource manager.
    public private(set) var metrics = ResourceManagerMetrics()
    
    /// Used to store callbacks for completion blocks.
    private var resourceCompletions: [String: [(Bool, String) -> Void]] = [:]
    
    private struct Observer {
        weak var instance: ResourceManagerObserver?
    }
    
    private var observers: [ObjectIdentifier: Observer] = [:]
    
    /// Returns all queues in an array for convenience.
    private var queues: [DownloadQueue] {
        return [downloadQueue, priorityQueue].compactMap { $0 }
    }
    
    // MARK: - Public Properties
    
    public var downloads: [Downloadable] {
        get async {
            var downloads: [Downloadable] = []
            for queue in queues {
                downloads += await queue.downloads
            }
            return downloads
        }
    }
    
    public var currentDownloads: [Downloadable] {
        get async {
            var downloads: [Downloadable] = []
            for queue in queues {
                downloads += await queue.currentDownloads
            }
            return downloads
        }
    }
    
    public var queuedDownloads: [Downloadable] {
        get async {
            var downloads: [Downloadable] = []
            for queue in queues {
                downloads += await queue.queuedDownloads
            }
            return downloads
        }
    }
    
    public var currentDownloadCount: Int {
        get async {
            var count = 0
            for queue in queues {
                count += await queue.currentDownloadCount
            }
            return count
        }
    }
    
    public var queuedDownloadCount: Int {
        get async {
            var count = 0
            for queue in queues {
                count += await queue.queuedDownloadCount
            }
            return count
        }
    }
    
    public var isActive: Bool {
        get async {
            return await downloadQueue.isActive
        }
    }
    
    // MARK: - Initialization
    
    public init(cache: any ResourceCachable, downloadQueue: DownloadQueue, priorityQueue: DownloadQueue? = nil) {
        self.cache = cache
        self.downloadQueue = downloadQueue
        self.priorityQueue = priorityQueue
    }
    
    // MARK: - Public Methods
    
    public func setActive(_ active: Bool) async {
        await downloadQueue.setActive(active)
        await priorityQueue?.setActive(active)
    }
    
    public func hasDownloadable(with identifier: String) async -> Bool {
        for queue in queues {
            if await queue.hasDownloadable(with: identifier) {
                return true
            }
        }
        return false
    }
    
    public func downloadable(for identifier: String) async -> Downloadable? {
        for queue in queues {
            if let downloadable = await queue.downloadable(for: identifier) {
                return downloadable
            }
        }
        return nil
    }
    
    public func isDownloading(for identifier: String) async -> Bool {
        for queue in queues {
            if await queue.isDownloading(for: identifier) {
                return true
            }
        }
        return false
    }
    
    /// Request downloads for the specified resources.
    /// - Parameters:
    ///   - resources: resources to download
    ///   - options: download options
    /// - Returns: list of download requests
    @discardableResult
    public func request(resources: [Resource], options: RequestOptions = RequestOptions()) async -> [DownloadRequest] {
        
        await downloadQueue.set(delegate: self)
        await priorityQueue?.set(delegate: self)
        
        let uniqueAssets = resources.unique(\.id)
        
        // Grab Assets we need from file manager, filtering out those that are already downloaded.
        let downloads = await cache.requestDownloads(assets: uniqueAssets, options: options)
        
        metrics.requested += uniqueAssets.count
                
        log.info("Requested unique asset count: \(uniqueAssets.count) Downloads: \(downloads.count)")
                
        guard downloads.count > 0 else {
            log.info("[AssetManager]: Metrics on no downloads: \(self.metrics.description)")
            return []
        }
        
        // We need to filter the downloads that are in progress, since there's not much we will do
        // in that case. For those that are in queue, we might move them to a higher priority queue.
        let finalDownloads = await downloads.filterAsync { download in 
            let identifier = await download.downloadableIdentifier()
            let isDownloading = await self.isDownloading(for: identifier)
            return !isDownloading
        }
                
        if downloads.count != finalDownloads.count {
            log.error("[AssetManager]: Final downloads mismatch: \(downloads.count) \(finalDownloads.count)")
        }
        
        if let priorityQueue = priorityQueue, options.downloadPriority == .high {
            // Move current priority queued downloads back to normal queue, because we have
            // a higher priority downloads now.
            let currentPriorityDownloads = await priorityQueue.queuedDownloads
            await priorityQueue.cancel(items: currentPriorityDownloads)
            
            let maxDownloadPriority = await downloadQueue.currentMaximumPriority() + 1
            
            for currentPriorityDownload in currentPriorityDownloads {
                await currentPriorityDownload.set(priority: maxDownloadPriority)
            }
            
            metrics.priorityIncreased += finalDownloads.count
            metrics.priorityDecreased += currentPriorityDownloads.count
            
            await downloadQueue.download(currentPriorityDownloads)
            
            await priorityQueue.download(finalDownloads.map { $0.mirror.downloadable })
            
            // If those downloads are on download queue and were now moved to priority,
            // we need to cancel them on download, so we do not download them twice.
            let normalQueuedDownloads = await finalDownloads.filterAsync {
                return await self.downloadQueue.hasDownloadable(with: await $0.downloadableIdentifier())
            }
            
            await downloadQueue.cancel(items: normalQueuedDownloads.map { $0.mirror.downloadable })
            
            // TODO: Log all downloadable identifiers by comma.
            //log.info("Reprioritising assets: \(finalDownloads.map({ $0.downloadableIdentifier() }).joined(separator: ", "))")
        }
        else {
            await downloadQueue.download(finalDownloads.map { $0.mirror.downloadable })
        }
        
        // Add downloads to monitor progresses.
        await progress.add(downloadItems: finalDownloads.map { $0.mirror.downloadable })
        
        log.info("[AssetManager]: Metrics on request: \(self.metrics.description)")
        
        return downloads
    }
    
    public func resume() async {
        await setActive(true)
        
        // Ensure delegates are set.
        await downloadQueue.set(delegate: self)
        await priorityQueue?.set(delegate: self)
                
        await downloadQueue.enqueuePending()
        await priorityQueue?.enqueuePending()
    }
    
    public func cancelAll() async {
        for queue in queues {
            await queue.cancelAll()
        }
        
        for (identifier, completions) in resourceCompletions {
            for completion in completions {
                completion(false, identifier)
            }
        }
        
        resourceCompletions.removeAll()
    }
    
    public func add(observer: ResourceManagerObserver) {
        self.observers[ObjectIdentifier(observer)] = Observer(instance: observer)
    }
    
    public func remove(observer: ResourceManagerObserver) {
        self.observers[ObjectIdentifier(observer)] = nil
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
    public func downloadQueue(_ queue: DownloadQueue, downloadDidStart downloadable: Downloadable, with processor: DownloadProcessor) async {
        guard let downloadRequest = await cache.downloadRequest(for: downloadable) else {
            return
        }
        
        self.metrics.downloadBegan += 1
        self.foreachObserver { $0.didStartDownloading(downloadRequest) }
    }
    
    public func downloadQueue(_ queue: DownloadQueue, downloadDidTransferData downloadable: Downloadable, using processor: DownloadProcessor) async {
        
        var tempMetrics = self.metrics
        await tempMetrics.updateDownloadSpeed(downloadable: downloadable)
        self.metrics = tempMetrics
    }
            
    public func downloadQueue(_ queue: DownloadQueue, downloadDidFinish downloadable: Downloadable, to location: URL) async {
        do {
            // Move the file to a temporary location, otherwise it gets removed by the system immediately after this function completes
            let tempLocation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-download.tmp")
            try FileManager.default.moveItem(at: location, to: tempLocation)
            
            // Store the file to the cache

            do {
                if let downloadRequest = try await self.cache.download(downloadable, didFinishTo: tempLocation) {
                    self.metrics.downloadCompleted += 1
                    let identifier = await downloadable.identifier
                    var tempMetrics = self.metrics
                    await tempMetrics.updateDownloadSpeed(downloadable: downloadable)
                    self.metrics = tempMetrics
                    
                    self.completeProgress(downloadRequest, downloadable: downloadable, with: nil)
                    
                    self.log.info("[AssetManager]: Download finished: \(identifier)")
                    
                    self.log.info("[AssetManager]: Metrics on download finished: \(self.metrics.description)")
                }
            }
            catch let error {
                self.log.error("[AssetManager]: Error caching file: \(error.localizedDescription)")
                await self.downloadQueue(queue, downloadDidFail: downloadable, with: error)
            }
        } catch let error {
            log.error("[AssetManager]: Error moving temporary file: \(error.localizedDescription)")

            // Ensure error is handled, download actually did fail.
            Task {
                await self.downloadQueue(queue, downloadDidFail: downloadable, with: error)
            }
        }
    }
    
    // Called when download had failed for any reason, including sessions being invalidated.
    public func downloadQueue(_ queue: DownloadQueue, downloadDidFail downloadable: Downloadable, with error: Error) async {
        let retryRequest = await self.cache.download(downloadable, didFailWith: error)
        
        // Check if we should retry, cache will tell us based on it's internal mirror policy.
        // We cannot switch queues here, if it was put on lower priority, it should stay on lower priority.
        if let retryRequest = retryRequest, let retry = retryRequest.retryRequest {
            let retryDownloadable = await retryRequest.downloadable()
            if let retryDownloadable = retryDownloadable {
                metrics.retried += 1
                var tempMetrics = metrics
                await tempMetrics.updateDownloadSpeed(downloadable: retryDownloadable)
                metrics = tempMetrics
                
                // Put it on the same queue.
                Task {
                    self.foreachObserver { $0.willRetryFailedDownload(retry, originalDownload: retryRequest.originalRequest, with: error) }
                }
                
                let identifier = await retryDownloadable.identifier
                log.error("[AssetManager]: Download failed, retrying: \(identifier) Error: \(error.localizedDescription)")
                
                await queue.download([retryDownloadable])
            }
        } else if let originalRequest = retryRequest?.originalRequest {
            metrics.failed += 1
            
            let identifier = await downloadable.identifier
            log.error("[AssetManager]: Download failed, done: \(identifier) Error: \(error.localizedDescription)")
                
            self.completeProgress(originalRequest, downloadable: downloadable, with: error)
        }
        
        log.info("[AssetManager]: Metrics on download failed: \(self.metrics.description)")
    }
}

// MARK: - Private Methods

extension ResourceManager {
    
    private func completeProgress(_ downloadRequest: DownloadRequest, downloadable: Downloadable, with error: Error?) {
        Task {
            let downloadableIdentifier = await downloadable.identifier
            await self.progress.complete(identifier: downloadableIdentifier, with: error)
            
            let identifier = await downloadRequest.resourceIdentifier()
            
            guard let completions = self.resourceCompletions[identifier] else {
                return
            }
            
            // Remove the completion from resources
            self.resourceCompletions[identifier] = nil
            
            // Execute callbacks
            for completion in completions {
                completion(error == nil, identifier)
            }
        }
    }
}

// MARK: - Resource Completion Callbacks

extension ResourceManager {
    /// Add a completion callback for a given resource identifier. Callback will be called once when the resource
    /// request either finishes or fails. The boolean will indicate success or failure.
    /// Note: If resource identifier doesn't exist, completion callback will be called immediately.
    /// - Parameters:
    ///   - identifier: resource identifier to add the callback for.
    ///   - completion: callback to call once resource is finished.
    public func addResourceCompletion(for identifier: String, completion: @escaping (Bool, String) -> Void) async {
        
        // Check if resource is already cached, if yes, complete immediately
        let currentAssets = await cache.currentAssets()
        if currentAssets.contains(where: { $0.id == identifier }) {
            completion(true, identifier)
            return
        }
        
        // Check if there is an ongoing download request for resource
        let currentDownloadRequests = await cache.currentDownloadRequests()
        let hasMatchingRequest = await currentDownloadRequests.asyncContains { await $0.resourceIdentifier() == identifier }
        if !hasMatchingRequest {
            // No download request exists, so this is a completed request with an error.
            completion(false, identifier)
            return
        }
        
        if var completions = resourceCompletions[identifier] {
            completions.append(completion)
            resourceCompletions[identifier] = completions
        } else {
            resourceCompletions[identifier] = [completion]
        }
    }
}
