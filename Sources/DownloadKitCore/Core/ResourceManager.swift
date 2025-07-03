//
//  ResourceManager.swift
//  DownloadKit
//
//  Created by Dal Rupnik on 2/5/21.
//

import Foundation
import os

public protocol ResourceManagerObserver: AnyObject, Sendable {
    func didStartDownloading(_ downloadRequest: DownloadRequest)
    func willRetryFailedDownload(_ downloadRequest: DownloadRequest, mirror: ResourceMirrorSelection, with error: Error)
    func didFinishDownload(_ downloadRequest: DownloadRequest, with error: Error?)
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
    
    private let log = Logger.logResourceManager
    
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
    
    public func request(resource: Resource, options: RequestOptions = RequestOptions()) async -> DownloadRequest? {
        return await request(resources: [resource], options: options).first
    }
    
    /// Request downloads for the specified resources.
    /// - Parameters:
    ///   - resources: resources to download
    ///   - options: download options
    /// - Returns: list of download requests
    @discardableResult
    public func request(resources: [Resource], options: RequestOptions = RequestOptions()) async -> [DownloadRequest] {
        
        await ensureObserverSetup()
        
        let uniqueResources = resources.unique(\.id)
        
        // Grab resources we need from file manager, filtering out those that are already downloaded.
        let requests = await cache.requestDownloads(resources: uniqueResources, options: options)
        
        metrics.requested += uniqueResources.count
        
        log.info("Requested unique resource count: \(uniqueResources.count) Downloads: \(requests.count)")
        
        guard requests.count > 0 else {
            log.info("Metrics on no downloads: \(self.metrics.description)")
            return []
        }
        
        return requests
    }
    
    public func process(request: DownloadRequest, priority: DownloadPriority = .normal) async {
        await ensureObserverSetup()
        
        let resourceId = request.resourceId
        let downloadable = request.mirror.downloadable
        
        if let priorityQueue = priorityQueue, priority.rawValue > 0 {
            
            // Only if urgent priority, we will cancel other priority downloads,
            // otherwise this just goes to priority queue based on download priority.
            if priority.rawValue > 1 {
                let currentPriorityDownloads = await priorityQueue.queuedDownloads
                await priorityQueue.cancel(items: currentPriorityDownloads)
                
                let maxDownloadPriority = await downloadQueue.currentMaximumPriority() + 1
                
                for currentPriorityDownload in currentPriorityDownloads {
                    await currentPriorityDownload.set(priority: maxDownloadPriority)
                }
                
                metrics.priorityDecreased += currentPriorityDownloads.count
                
                await downloadQueue.download(currentPriorityDownloads)
            }
            
            metrics.priorityIncreased += 1
            
            await priorityQueue.download(request.mirror.downloadable)
            
            // If download is on previous queue, we need to cancel, so we do not download it twice.
            let downloadableIdentifier = await request.downloadableIdentifier()
            
            if await downloadQueue.hasDownloadable(with: downloadableIdentifier) {
                await downloadQueue.cancel(with: downloadableIdentifier)
            }
            
            log.info("Reprioritising resource: \(resourceId)")
        }
        else {
            await downloadQueue.download(request.mirror.downloadable)
        }
        
        // Add downloads to monitor progresses.
        await progress.add(downloadItem: downloadable)
        
        log.info("Metrics on request: \(self.metrics.description)")
    }
    
    public func process(requests: [DownloadRequest], priority: DownloadPriority = .normal) async {
        
        // We need to filter the downloads that are in progress, since there's not much we will do
        // in that case. For those that are in queue, we might move them to a higher priority queue.
        let finalRequests = await requests.filterAsync { download in
            let identifier = await download.downloadableIdentifier()
            let isDownloading = await self.isDownloading(for: identifier)
            return !isDownloading
        }
                
        if requests.count != finalRequests.count {
            log.error("Final downloads mismatch: \(requests.count) \(finalRequests.count)")
        }
        
        var finalPriority = priority
        
        if let priorityQueue = priorityQueue, priority.rawValue > 0 {
            // Move current priority queued downloads back to normal queue, because we have
            // a higher priority downloads now.
            if priority == .urgent {
                let currentPriorityDownloads = await priorityQueue.queuedDownloads
                await priorityQueue.cancel(items: currentPriorityDownloads)
                
                let maxDownloadPriority = await downloadQueue.currentMaximumPriority() + 1
                
                for currentPriorityDownload in currentPriorityDownloads {
                    await currentPriorityDownload.set(priority: maxDownloadPriority)
                }
                
                metrics.priorityDecreased += currentPriorityDownloads.count
                
                await downloadQueue.download(currentPriorityDownloads)
                
                // Since all downloads were cancelled as urgent, reduce priority,
                // since otherwise each file will cancel out previous download,
                // so the priotity is kept high for all files in this "batch".
                finalPriority = .high
            }
                        
            // Log all downloadable identifiers being reprioritized
            var identifiers: [String] = []
            for download in requests {
                identifiers.append(await download.downloadableIdentifier())
            }
            log.info("Reprioritised resources: \(identifiers.joined(separator: ", "))")
        }
        
        // Process the requests.
        for request in finalRequests {
            await process(request: request, priority: finalPriority)
        }
    }
    
    public func resume() async {
        await ensureObserverSetup()
        
        await setActive(true)
        
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
    
    private func ensureObserverSetup() async {
        await downloadQueue.set(observer: self)
        await priorityQueue?.set(observer: self)
    }
}

// MARK: - DownloadQueueObserver

extension ResourceManager: DownloadQueueObserver {
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
 
        // Store the file to the cache
        do {
            if let downloadRequest = try await self.cache.download(downloadable, didFinishTo: location) {
                self.metrics.downloadCompleted += 1
                let identifier = await downloadable.identifier
                var tempMetrics = self.metrics
                await tempMetrics.updateDownloadSpeed(downloadable: downloadable)
                self.metrics = tempMetrics
                
                log.info("Download finished: \(identifier)")
                
                log.info("Metrics on download finished: \(self.metrics.description)")
                
                await self.completeProgress(downloadRequest, downloadable: downloadable, with: nil)
            }
        }
        catch let error {
            log.error("Error caching file: \(error.localizedDescription)")
            await self.downloadQueue(queue, downloadDidFail: downloadable, with: error)
        }
    }
    
    // Called when download had failed for any reason, including sessions being invalidated.
    public func downloadQueue(_ queue: DownloadQueue, downloadDidFail downloadable: Downloadable, with error: Error) async {
        let retryRequest = await self.cache.download(downloadable, didFailWith: error)
        
        // Check if we should retry, cache will tell us based on it's internal mirror policy.
        // We cannot switch queues here, if it was put on lower priority, it should stay on lower priority.
        if let retryRequest = retryRequest, let retry = retryRequest.nextMirror {
            let retryDownloadable = await retryRequest.downloadable()
            if let retryDownloadable = retryDownloadable {
                metrics.retried += 1
                var tempMetrics = metrics
                await tempMetrics.updateDownloadSpeed(downloadable: retryDownloadable)
                metrics = tempMetrics
                
                self.foreachObserver { $0.willRetryFailedDownload(retryRequest.request, mirror: retry, with: error) }
                
                let identifier = await retryDownloadable.identifier
                log.error("Download failed, retrying: \(identifier) Error: \(error.localizedDescription)")
                
                await queue.download([retryDownloadable])
            }
        } else if let retryRequest = retryRequest {
            metrics.failed += 1
            
            let identifier = await downloadable.identifier
            log.error("Download failed, done: \(identifier) Error: \(error.localizedDescription)")
                
            await self.completeProgress(retryRequest.request, downloadable: downloadable, with: error)
        }
        else {
            log.fault("Download received, but cache knows nothing about this resource, not OK.")
        }
        
        log.info("Metrics on download failed: \(self.metrics.description)")
    }
}

// MARK: - Private Methods

extension ResourceManager {
    
    private func completeProgress(_ downloadRequest: DownloadRequest, downloadable: Downloadable, with error: Error?) async {
            let downloadableIdentifier = await downloadable.identifier
            await self.progress.complete(identifier: downloadableIdentifier, with: error)
            
            let identifier = downloadRequest.resourceId
            
            guard let completions = self.resourceCompletions[identifier] else {
                return
            }
            
            // Remove the completion from resources
            self.resourceCompletions[identifier] = nil
            
            // Execute callbacks
            for completion in completions {
                completion(error == nil, identifier)
            }
            
            self.foreachObserver {
                $0.didFinishDownload(downloadRequest, with: error)
            }
    }
}

// MARK: - Resource Completion Callbacks

extension ResourceManager {
    public func addResourceCompletion(for resource: ResourceFile, completion: @Sendable @escaping (Bool, String) -> Void) async {
        // Check if any of the mirrors have downloadable.
        
        let identifier = resource.id
             
        if var completions = resourceCompletions[identifier] {
            completions.append(completion)
            resourceCompletions[identifier] = completions
        } else {
            resourceCompletions[identifier] = [completion]
        }
    }
    
    public func removeResourceCompletion(for resource: ResourceFile) {
        resourceCompletions[resource.id] = nil
    }
}
