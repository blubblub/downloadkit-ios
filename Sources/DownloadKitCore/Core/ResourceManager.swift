//
//  ResourceManager.swift
//  DownloadKit
//
//  Created by Dal Rupnik on 2/5/21.
//

import Foundation
import os

public protocol ResourceManagerObserver: AnyObject, Sendable {
    func didStartDownloading(_ downloadRequest: DownloadRequest) async
    func willRetryFailedDownload(_ downloadRequest: DownloadRequest, mirror: ResourceMirrorSelection, with error: Error) async
    func didFinishDownload(_ downloadRequest: DownloadRequest, with error: Error?) async
}

/// ResourceManager manages a set of resources, allowing a user to request downloads from multiple mirrors,
/// managing caching and retries internally.
public final class ResourceManager: ResourceRetrievable, DownloadQueuable {
    
    private actor ResourceManagerState {
        struct Observer {
            weak var instance: ResourceManagerObserver?
        }
        
        private var currentObservers: [ObjectIdentifier: Observer] = [:]
        
        private var requests: [DownloadRequest] = []
        
        var observers: [ObjectIdentifier: Observer] {
            get {
                // Cleanup deallocated observer wrappers automatically
                for key in currentObservers.compactMap({ $1.instance == nil ? $0 : nil }) {
                    currentObservers[key] = nil
                }
                
                return currentObservers
            }
        }
        
        /// Used to store callbacks for completion blocks.
        var resourceCompletions: [String: [@Sendable (Bool, String) -> Void]] = [:]
        
        func addResourceCompletion(_ resourceKey: String, _ completion: @escaping @Sendable (Bool, String) -> Void) {
            if resourceCompletions[resourceKey] == nil {
                resourceCompletions[resourceKey] = [completion]
            } else {
                resourceCompletions[resourceKey]?.append(completion)
            }
        }
        
        func removeResourceCompletions(for id: String) {
            resourceCompletions[id] = nil
        }
        
        func removeAllResourceCompletions() {
            resourceCompletions.removeAll()
        }
        
        func addObserver(_ observer: ResourceManagerObserver) {
            currentObservers[ObjectIdentifier(observer)] = .init(instance: observer)
        }
        
        func removeObserver(_ observer: ResourceManagerObserver) {
            currentObservers[ObjectIdentifier(observer)] = nil
        }
    }

    // MARK: - Private Properties
    
    /// Queue for downloading resources.
    private let downloadQueue: DownloadQueue
    
    /// Priority queue for high priority downloads.
    private let priorityQueue: DownloadQueue?
    
    /// Cache where resource files are stored.
    public let cache: any ResourceCachable
    
    /// Progress tracker for all resource downloads.
    public let progress = ResourceDownloadProgress()
    
    private let log = Logger.logResourceManager
    
    private let state = ResourceManagerState()
    public let metrics = ResourceManagerMetrics()
    
    
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
    
    public static func create(cache: any ResourceCachable, sessionConfiguration: URLSessionConfiguration? = nil, prioritySessionConfiguration: URLSessionConfiguration? = nil) -> ResourceManager {
        
        let downloadProcessor : WebDownloadProcessor
        
        if let sessionConfiguration {
            downloadProcessor = WebDownloadProcessor(configuration: sessionConfiguration)
        }
        else {
            downloadProcessor = WebDownloadProcessor()
        }
        
        let priorityDownloadProcessor: WebDownloadProcessor
        
        if let prioritySessionConfiguration {
            priorityDownloadProcessor = WebDownloadProcessor(configuration: prioritySessionConfiguration)
        }
        else {
            
            priorityDownloadProcessor = WebDownloadProcessor.priorityProcessor()
        }
                
        let downloadQueue = DownloadQueue(processors: [ downloadProcessor ])
        let priorityQueue = DownloadQueue(processors: [ priorityDownloadProcessor ], simultaneousDownloads: 30)
        
        return ResourceManager(cache: cache, downloadQueue: downloadQueue, priorityQueue: priorityQueue)
    }
    
    // MARK: - Initialization
    
    public init(cache: any ResourceCachable, downloadQueue: DownloadQueue, priorityQueue: DownloadQueue? = nil) {
        self.cache = cache
        self.downloadQueue = downloadQueue
        self.priorityQueue = priorityQueue
    }
    
    // MARK: - ResourceRetrievable
    
    public func fileURL(for id: String) -> URL? {
        return cache.fileURL(for: id)
    }
    
    public func data(for id: String) -> Data? {
        return cache.data(for: id)
    }
    
    public func image(for id: String) -> LocalImage? {
        return cache.image(for: id)
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
    
    public func request(resource: ResourceFile, options: RequestOptions = RequestOptions()) async -> DownloadRequest? {
        return await request(resources: [resource], options: options).first
    }
    
    /// Request downloads for the specified resources.
    /// - Parameters:
    ///   - resources: resources to download
    ///   - options: download options
    /// - Returns: list of download requests
    @discardableResult
    public func request(resources: [ResourceFile], options: RequestOptions = RequestOptions()) async -> [DownloadRequest] {
        
        await ensureObserverSetup()
        
        let uniqueResources = resources.unique(\.id)
        
        // Grab resources we need from file manager, filtering out those that are already downloaded.
        let requests = await cache.requestDownloads(resources: uniqueResources, options: options)
        
        await metrics.increase(requested: uniqueResources.count)
        
        log.info("Requested unique resource count: \(uniqueResources.count) Downloads: \(requests.count)")
        
        guard requests.count > 0 else {
            let metrics = await self.metrics.description
            log.info("Metrics on no downloads: \(metrics)")
            return []
        }
        
        return requests
    }
    
    public func process(request: DownloadRequest, priority: DownloadPriority = .normal) async {
        await ensureObserverSetup()
        
        let requestId = request.id
        let downloadable = request.mirror.downloadable
        
        // Tell cache it needs to track the request, as it will be processed.
        await cache.processDownload(request)

        // Add downloads to monitor progresses.
        await progress.add(downloadItem: downloadable)
        
        if let priorityQueue = priorityQueue, priority.rawValue > 0 {
            
            // Handle urgent priority downloads
            if priority.rawValue > 1 {
                await reprioritise(priorityQueue: priorityQueue)
            }
            
            await metrics.increase(priorityIncreased: 1)
            
            await priorityQueue.download(request.mirror.downloadable)
            
            // If download is on previous queue, we need to cancel, so we do not download it twice.
            let downloadableIdentifier = await request.downloadableIdentifier()
            
            if await downloadQueue.hasDownloadable(with: downloadableIdentifier) {
                await downloadQueue.cancel(with: downloadableIdentifier)
            }
            
            log.info("Reprioritising resource: \(requestId)")
        }
        else {
            await downloadQueue.download(request.mirror.downloadable)
        }
        
        let metrics = await metrics.description
        log.info("Metrics on request: \(metrics)")
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
                await reprioritise(priorityQueue: priorityQueue)
                
                // Since all downloads were cancelled as urgent, reduce priority,
                // since otherwise each file will cancel out previous download,
                // so the priority is kept high for all files in this "batch".
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
        
        for (identifier, completions) in await state.resourceCompletions {
            for completion in completions {
                completion(false, identifier)
            }
        }
        
        await state.removeAllResourceCompletions()
    }
    
    public func cancel(request: DownloadRequest) async {
        let downloadableIdentifier = await request.downloadableIdentifier()
        
        // Cancel the download from both queues - it will only exist in one of them
        await downloadQueue.cancel(with: downloadableIdentifier)
        await priorityQueue?.cancel(with: downloadableIdentifier)
        
        _ = await cache.download(request.mirror.downloadable, didFailWith: DownloadKitError.networkError(.cancelled))
        
        // Complete the request with cancellation
        
        // Remove progress tracking
        await progress.complete(identifier: downloadableIdentifier, with: DownloadKitError.networkError(.cancelled))
        
        // Execute and remove any completion handlers for this resource
        let resourceId = request.id
        if let completions = await state.resourceCompletions[resourceId] {
            await state.removeResourceCompletions(for: resourceId)
            
            for completion in completions {
                completion(false, resourceId)
            }
        }
        
        log.info("Cancelled download request: \(resourceId)")
    }
    
    public func cancel(requests: [DownloadRequest]) async {
        for request in requests {
            await cancel(request: request)
        }
    }
    
    public func add(observer: ResourceManagerObserver) async {
        await state.addObserver(observer)
    }
    
    public func remove(observer: ResourceManagerObserver) async {
        await state.removeObserver(observer)
    }
    
    private func foreachObserver(action: (ResourceManagerObserver) async -> Void) async {
        
        for observer in await state.observers {
            guard let instance = observer.value.instance else { continue }
            await action(instance)
        }
    }
    
    private func ensureObserverSetup() async {
        await downloadQueue.set(observer: self)
        await priorityQueue?.set(observer: self)
    }
    
    /// Handles urgent priority downloads by moving current priority queue downloads to the normal queue.
    /// This method extracts the common logic for urgent priority handling that was duplicated
    /// in both single and batch request processing methods.
    /// - Parameter priorityQueue: The priority queue from which to move downloads
    private func reprioritise(priorityQueue: DownloadQueue) async {
        let currentPriorityDownloads = await priorityQueue.queuedDownloads
        await priorityQueue.cancel(items: currentPriorityDownloads)
        
        let maxDownloadPriority = await downloadQueue.currentMaximumPriority + 1
        
        for currentPriorityDownload in currentPriorityDownloads {
            await currentPriorityDownload.set(priority: maxDownloadPriority)
        }
        
        await metrics.increase(priorityDecreased: currentPriorityDownloads.count)
        
        await downloadQueue.download(currentPriorityDownloads)
    }
}

// MARK: - DownloadQueueObserver

extension ResourceManager: DownloadQueueObserver {
    public func downloadQueue(_ queue: DownloadQueue, downloadDidStart downloadable: Downloadable, with processor: DownloadProcessor) async {
        guard let downloadRequest = await cache.downloadRequests(for: downloadable).first else {
            log.error("NO-OP: Download did start, but no download request found in cache. Inconsistent state.")
            return
        }
        
        await metrics.increase(downloadBegan: 1)
        await self.foreachObserver { await $0.didStartDownloading(downloadRequest) }
    }
    
    public func downloadQueue(_ queue: DownloadQueue, downloadDidTransferData downloadable: Downloadable, using processor: DownloadProcessor) async {
        await metrics.updateDownloadSpeed(downloadable: downloadable)
    }
            
    public func downloadQueue(_ queue: DownloadQueue, downloadDidFinish downloadable: Downloadable, to location: URL) async {
 
        // Store the file to the cache
        do {
            
            let identifier = await downloadable.identifier
            
            if let downloadRequest = try await self.cache.download(downloadable, didFinishTo: location) {
                
                await metrics.increase(downloadCompleted: 1)
                
                await metrics.updateDownloadSpeed(downloadable: downloadable, isCompleted: true)
                
                log.info("Download finished: \(identifier) request: \(downloadRequest.id)")
                
                let metrics = await self.metrics.description
                log.info("Metrics on download finished: \(metrics)")
                
                await self.completeProgress(downloadRequest, downloadable: downloadable, with: nil)
            }
            else {
                log.fault("NO-OP: Download did finish: \(identifier), request not found.")
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
                
                await metrics.increase(retried: 1)
                await metrics.updateDownloadSpeed(downloadable: retryDownloadable)
                
                await self.foreachObserver { await $0.willRetryFailedDownload(retryRequest.request, mirror: retry, with: error) }
                
                let identifier = await retryDownloadable.identifier
                log.error("Download failed, retrying: \(identifier) Error: \(error.localizedDescription)")
                
                await queue.download([retryDownloadable])
            }
        } else if let retryRequest = retryRequest {
            await metrics.increase(failed: 1)
            
            let identifier = await downloadable.identifier
            log.error("Download failed, done: \(identifier) Error: \(error.localizedDescription)")
                
            await self.completeProgress(retryRequest.request, downloadable: downloadable, with: error)
        }
        else {
            log.fault("Download received, but cache knows nothing about this resource, not OK.")
        }
        
        let metrics = await metrics.description
        log.info("Metrics on download failed: \(metrics)")
    }
}

// MARK: - Private Methods

extension ResourceManager {
    
    private func completeProgress(_ downloadRequest: DownloadRequest, downloadable: Downloadable, with error: Error?) async {
        let downloadableIdentifier = await downloadable.identifier
        await self.progress.complete(identifier: downloadableIdentifier, with: error)
        
        let identifier = downloadRequest.resource.id
        
        guard let completions = await self.state.resourceCompletions[identifier] else {
            return
        }
        
        // Remove the completion from resources
        await state.removeResourceCompletions(for: identifier)
        
        // Execute callbacks
        for completion in completions {
            completion(error == nil, identifier)
        }
        
        await self.foreachObserver {
            await $0.didFinishDownload(downloadRequest, with: error)
        }
    }
}

// MARK: - Resource Completion Callbacks

extension ResourceManager {
    public func addResourceCompletion(for resource: ResourceFile, completion: @Sendable @escaping (Bool, String) -> Void) async {
        // Check if any of the mirrors have downloadable.
        
        let identifier = resource.id
        
        await state.addResourceCompletion(identifier, completion)
    }
    
    public func removeResourceCompletion(for resource: ResourceFile) async {
        await state.removeResourceCompletions(for: resource.id)
    }
}
