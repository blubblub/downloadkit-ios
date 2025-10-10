//
//  ResourceManager.swift
//  DownloadKit
//
//  Created by Dal Rupnik on 2/5/21.
//

import Foundation
import os

public protocol ResourceManagerObserver: AnyObject, Sendable {
    func didStartDownloading(_ downloadTask: DownloadTask) async
    func willRetryFailedDownload(_ downloadTask: DownloadTask, downloadable: Downloadable, with error: Error) async
    func didFinishDownload(_ downloadTask: DownloadTask, with error: Error?) async
}

/// ResourceManager manages a set of resources, allowing a user to request downloads from multiple mirrors,
/// managing caching and retries internally.
public final class ResourceManager: ResourceRetrievable, DownloadQueuable {
    
    private actor ResourceManagerState {
        struct Observer {
            weak var instance: ResourceManagerObserver?
        }
        
        private var currentObservers: [ObjectIdentifier: Observer] = [:]
        
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
    
    public var downloads: [DownloadTask] {
        get async {
            var downloads: [DownloadTask] = []
            for queue in queues {
                downloads += await queue.downloads
            }
            return downloads
        }
    }
    
    public var currentDownloads: [DownloadTask] {
        get async {
            var downloads: [DownloadTask] = []
            for queue in queues {
                downloads += await queue.currentDownloads
            }
            return downloads
        }
    }
    
    public var queuedDownloads: [DownloadTask] {
        get async {
            var downloads: [DownloadTask] = []
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
    
    public func hasDownload(for identifier: String) async -> Bool {
        for queue in queues {
            if await queue.hasDownload(for: identifier) {
                return true
            }
        }
        return false
    }
    
    public func download(for identifier: String) async -> DownloadTask? {
        for queue in queues {
            if let downloadable = await queue.download(for: identifier) {
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
                
        log.info("Requested unique resource count: \(uniqueResources.count) Downloads: \(requests.count)")
        
        guard requests.count > 0 else {
            let metrics = await self.metrics.description
            log.info("Metrics on no downloads: \(metrics)")
            return []
        }
        
        return requests
    }
    
    public func updateStorage(for resources: [ResourceFile], storage: StoragePriority) {
        cache.updateStorage(resources: resources, storage: storage)
    }
    
    public func process(request: DownloadRequest, priority: DownloadPriority = .normal) async -> DownloadTask {
        await ensureObserverSetup()
                
        let task = DownloadTask(request: request, mirrorPolicy: WeightedMirrorPolicy())
        
        log.info("Start processing requested: \(task.id)")
        
        await metrics.increase(requested: 1)
        
        // Tell cache it needs to track the task, as it will be processed. If cache says NO, it means
        // it already has the file.
        let downloadProcessingState = await cache.download(startProcessing: task)
        
        if !downloadProcessingState.shouldDownload {
            log.info("Processed a download that already exists: \(task.id)")
            
            if downloadProcessingState.isFinished {
                log.debug("Download is already finished, completing progress: \(task.id)")
                await completeProgress(downloadTask: task, with: nil)
            }
            return task
        }
        
        log.debug("Processing started for request: \(task.id)")

        
        if let priorityQueue = priorityQueue, priority.rawValue > 0 {
            
            // Handle urgent priority downloads
            if priority.rawValue > 1 {
                await reprioritise(priorityQueue: priorityQueue)
            }
            
            await metrics.increase(priorityIncreased: 1)
            
            await priorityQueue.download(task)
            
            // If download is on previous queue, we need to cancel, so we do not download it twice.
            
            if await downloadQueue.hasDownload(for: task.id) {
                await downloadQueue.cancel(with: task.id)
            }
            
            log.info("Reprioritising resource: \(task.id)")
        }
        else {
            
            log.debug("Enqueueing - \(task.id)")
            await downloadQueue.download(task)
        }
        
        let metrics = await metrics.description
        log.info("Metrics on request: \(metrics)")
        
        return task
    }
    
    public func process(requests: [DownloadRequest], priority: DownloadPriority = .normal) async -> [DownloadTask] {
        
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
                identifiers.append(download.id)
            }
            log.info("Reprioritised resources: \(identifiers.joined(separator: ", "))")
        }
        
        // Process the requests.
        var tasks = [DownloadTask]()
        for request in requests {
            let task = await process(request: request, priority: finalPriority)
            tasks.append(task)
        }
        
        return tasks
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
    
    public func cancel(_ download: DownloadTask) async {
        // Cancel the download from both queues - it will only exist in one of them
        await downloadQueue.cancel(with: download.id)
        await priorityQueue?.cancel(with: download.id)
        
        _ = await cache.download(download, didFailWith: DownloadKitError.networkError(.cancelled))
        
        // Complete the request with cancellation
        
        // Remove progress tracking
        await progress.complete(identifier: download.id, with: DownloadKitError.networkError(.cancelled))
        
        // Execute and remove any completion handlers for this resource
        let resourceId = download.id
        if let completions = await state.resourceCompletions[resourceId] {
            await state.removeResourceCompletions(for: resourceId)
            
            for completion in completions {
                completion(false, resourceId)
            }
        }
        
        log.info("Cancelled download request: \(resourceId)")
    }
    
    public func cancel(downloadTasks: [DownloadTask]) async {
        for download in downloadTasks {
            await cancel(download)
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
        
        await metrics.increase(priorityDecreased: currentPriorityDownloads.count)
        
        await downloadQueue.download(currentPriorityDownloads)
    }
}

// MARK: - DownloadQueueObserver

extension ResourceManager: DownloadQueueObserver {
    public func downloadQueue(_ queue: DownloadQueue, downloadDidStart downloadTask: DownloadTask, downloadable: Downloadable, on processor: any DownloadProcessor) async {
        
        // Add downloads to monitor progresses.
        await progress.add(download: downloadTask, downloadable: downloadable)
        
        await metrics.increase(downloadBegan: 1)
        await self.foreachObserver { await $0.didStartDownloading(downloadTask) }
    }
    
    public func downloadQueue(_ queue: DownloadQueue, downloadDidTransferData downloadTask: DownloadTask, downloadable: Downloadable, using processor: any DownloadProcessor) async {
        await metrics.updateDownloadSpeed(for: downloadTask, downloadable: downloadable)
    }
    
    public func downloadQueue(_ queue: DownloadQueue, downloadDidFinish task: DownloadTask, downloadable: Downloadable, to location: URL) async throws {
 
        // Store the file to the cache
        try await self.cache.download(task, downloadable: downloadable, didFinishTo: location)
        
        await metrics.increase(downloadCompleted: 1)
        await metrics.updateDownloadSpeed(for: task, downloadable: downloadable, isCompleted: true)

        let metrics = await self.metrics.description
        log.info("Metrics on download finished: \(metrics)")
        
        await self.completeProgress(downloadTask: task, with: nil)
    }
    
    // Called when download had failed for any reason, including sessions being invalidated.
    public func downloadQueue(_ queue: DownloadQueue, downloadDidFail downloadTask: DownloadTask, with error: Error) async {
        
        log.error("Download failed, done: \(downloadTask.id) Error: \(error.localizedDescription)")
        
        await metrics.increase(failed: 1)
        await self.cache.download(downloadTask, didFailWith: error)
        
        await self.completeProgress(downloadTask: downloadTask, with: error)
    
        let metrics = await metrics.description
        log.info("Metrics on download failed: \(metrics)")
        
        await self.foreachObserver { await $0.didFinishDownload(downloadTask, with: error) }
    }
    
    public func downloadQueue(_ queue: DownloadQueue, downloadWillRetry downloadTask: DownloadTask, context: DownloadRetryContext) async {
        let downloadable = context.nextDownloadable
        
        // Update progress.
        await progress.add(download: downloadTask, downloadable: downloadable)
        
        await metrics.increase(retried: 1)
        await metrics.updateDownloadSpeed(for: downloadTask, downloadable: downloadable)
        
        await self.foreachObserver { await $0.willRetryFailedDownload(downloadTask, downloadable: downloadable, with: context.error) }
    }
    
}

// MARK: - Private Methods

extension ResourceManager {
    
    private func completeProgress(downloadTask: DownloadTask, with error: Error?) async {
        await self.progress.complete(identifier: downloadTask.id, with: error)
        
        guard let completions = await self.state.resourceCompletions[downloadTask.id] else {
            // Even if there's no resource completions, still let observers know.
            await self.foreachObserver {
                await $0.didFinishDownload(downloadTask, with: error)
            }
            
            return
        }
        
        // Remove the completion from resources
        await state.removeResourceCompletions(for: downloadTask.id)
        
        // Execute callbacks
        for completion in completions {
            completion(error == nil, downloadTask.id)
        }
        
        await self.foreachObserver {
            await $0.didFinishDownload(downloadTask, with: error)
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
