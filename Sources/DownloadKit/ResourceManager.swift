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

public enum DownloadPriority : Sendable{
    case normal
    case high
}

public enum StoragePriority: String, Sendable {
    /// Cache Manager should permanently store the file. This should be used for offline mode.
    case permanent
    
    /// Cache Manager should place the file in temporary folder. Once system clears the folder
    /// due to space constraints, it will have to be redownloaded.
    case cached
}

public struct RequestOptions : Sendable {
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
public actor ResourceManager {
    private struct Observer {
        private(set) weak var instance: ResourceManagerObserver?
    }
    
    // MARK: - Private Properties
    
    private var assetCompletions: [String: [ProgressCompletion]] = [:]
    private var observers: [ObjectIdentifier: Observer] = [:]

    // MARK: - Public Properties
    public var log: os.Logger = logDK
        
    public let downloadQueue: DownloadQueue
    public let priorityQueue: DownloadQueue?
    
    private var queues: [DownloadQueue] {
        return [priorityQueue, downloadQueue].compactMap { $0 }
    }
    
    public let cache: any ResourceCachable
    
    public let progress = ResourceDownloadProgress()
    
    public private(set) var metrics = ResourceManagerMetrics()
    
    public static func build(with cache: ResourceCachable) async -> ResourceManager {
        let downloadQueue = DownloadQueue()
        await downloadQueue.add(processor: WebDownloadProcessor())
        
        let priorityQueue = DownloadQueue()
        await priorityQueue.add(processor: WebDownloadProcessor.priorityProcessor())
        await priorityQueue.set(simultaneousDownloads: 30)
        
        return .init(cache: cache, downloadQueue: downloadQueue, priorityQueue: priorityQueue)
    }
    
    
    /// Designated initializer for AssetManager.
    /// - Parameters:
    ///   - cache: Cache Manager to use
    ///   - downloadQueue: Normal Download Queue
    ///   - priorityQueue: Priority Download Queue (to quickly download)
    public init(cache: ResourceCachable, downloadQueue: DownloadQueue, priorityQueue: DownloadQueue? = nil) {
        self.cache = cache
        self.downloadQueue = downloadQueue
        self.priorityQueue = priorityQueue
    }
    
    @discardableResult
    public func request(resources: [ResourceFile]) async -> [DownloadRequest] {
        return await request(resources: resources, options: RequestOptions())
    }
    
    @discardableResult
    public func request(resources: [ResourceFile], options: RequestOptions) async -> [DownloadRequest] {
        
        // Ensure delegates are set and manager is active.
        await setActive(true)
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
        
        for (identifier, completions) in assetCompletions {
            for completion in completions {
                completion(false, identifier)
            }
        }
        
        assetCompletions.removeAll()
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
        else {
            let identifier = await downloadable.identifier
            log.error("[AssetManager]: Download failed, unknown: \(identifier) Error: \(error.localizedDescription)")
        }
        
        log.info("[AssetManager]: Metrics on download failed: \(self.metrics.description)")
    }
    
    private func completeProgress(_ downloadRequest: DownloadRequest, downloadable: Downloadable, with error: Error?) {
        if let completions = self.assetCompletions[downloadRequest.id] {
            for completion in completions {
                completion(error == nil, downloadRequest.id)
            }
            
            removeAssetCompletion(for: downloadRequest.id)
        }
        
        if let error = error {
            self.foreachObserver { $0.didFailToDownload(downloadRequest, with: error) }
        } else {
            self.foreachObserver { $0.didFinishDownloading(downloadRequest) }
        }
        
        Task {
            let identifier = await downloadable.identifier
            await progress.complete(identifier: identifier, with: error)
        }
    }
}

extension ResourceManager {
    public func addAssetCompletion(for identifier: String, with completion: @escaping ProgressCompletion) {
        // If this asset is not downloading at all, call the closure immediately!
        Task {
            guard await hasDownloadable(with: identifier) else {
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
    }
    
    public func removeAssetCompletion(for identifier: String) {
        assetCompletions[identifier] = nil
    }
}

// MARK: - Convenience Methods to downloads

extension ResourceManager: DownloadQueuable {
    
    public var isActive: Bool {
        get async {
            let states = await withTaskGroup(of: Bool.self) { group in
                var results: [Bool] = []
                for queue in queues {
                    group.addTask {
                        await queue.isActive
                    }
                }
                for await result in group {
                    results.append(result)
                }
                return results
            }
            return states.contains(true)
        }
    }
    
    public var currentDownloadCount: Int {
        get async {
            let counts = await withTaskGroup(of: Int.self) { group in
                var results: [Int] = []
                for queue in queues {
                    group.addTask {
                        await queue.currentDownloadCount
                    }
                }
                for await result in group {
                    results.append(result)
                }
                return results
            }
            return counts.reduce(0, +)
        }
    }
    
    public var queuedDownloadCount: Int {
        get async {
            let counts = await withTaskGroup(of: Int.self) { group in
                var results: [Int] = []
                for queue in queues {
                    group.addTask {
                        await queue.queuedDownloadCount
                    }
                }
                for await result in group {
                    results.append(result)
                }
                return results
            }
            return counts.reduce(0, +)
        }
    }
    
    public var downloads: [Downloadable] {
        get async {
            let allDownloads = await withTaskGroup(of: [Downloadable].self) { group in
                var results: [[Downloadable]] = []
                for queue in queues {
                    group.addTask {
                        await queue.downloads
                    }
                }
                for await result in group {
                    results.append(result)
                }
                return results
            }
            return allDownloads.flatMap { $0 }
        }
    }
    
    public var currentDownloads: [Downloadable] {
        get async {
            let allDownloads = await withTaskGroup(of: [Downloadable].self) { group in
                var results: [[Downloadable]] = []
                for queue in queues {
                    group.addTask {
                        await queue.currentDownloads
                    }
                }
                for await result in group {
                    results.append(result)
                }
                return results
            }
            return allDownloads.flatMap { $0 }
        }
    }
    
    public var queuedDownloads: [Downloadable] {
        get async {
            let allDownloads = await withTaskGroup(of: [Downloadable].self) { group in
                var results: [[Downloadable]] = []
                for queue in queues {
                    group.addTask {
                        await queue.queuedDownloads
                    }
                }
                for await result in group {
                    results.append(result)
                }
                return results
            }
            return allDownloads.flatMap { $0 }
        }
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
    
    public func setActive(_ value: Bool) async {
        await downloadQueue.setActive(value)
        await priorityQueue?.setActive(value)
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

extension Array where Element: Sendable {
    public func filterAsync(_ transform: @escaping @Sendable (Element) async -> Bool) async -> [Element] {
        var finalResult = Array<Element>()
        
        for element in self {
            if await transform(element) {
                finalResult.append(element)
            }
        }
        
        return finalResult
    }
}
