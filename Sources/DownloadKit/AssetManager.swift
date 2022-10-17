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

public protocol AssetManagerObserver: AnyObject {
    func didFinishDownloading(assetId: String)
    func didFailToDownload(assetId: String, with error: Error)
}

/// Completion block, having success flag and item identifier
public typealias ProgressCompletion = (Bool, String) -> Void

public enum DownloadPriority {
    case normal
    case high
}

public enum StoragePriority: String {
    /// Cache Manager should place the file in temporary folder. Once system clears the folder
    /// due to space constraints, it will have to be redownloaded.
    case cached
    
    /// Cache Manager should permanently store the file. This should be used for offline mode.
    case permanent
}

public struct RequestOptions {
    var downloadPriority: DownloadPriority = .normal
    var storagePriority: StoragePriority = .cached
    
    public init(downloadPriority: DownloadPriority = .normal,
                storagePriority: StoragePriority = .cached) {
        self.downloadPriority = downloadPriority
        self.storagePriority = storagePriority
    }
}

public struct AssetManagerMetrics {
    var requested = 0
    var downloadBegan = 0
    var downloadCompleted = 0
    var priorityIncreased = 0
    var priorityDecreased = 0
    var failed = 0
    var retried = 0
}

extension AssetManagerMetrics : CustomStringConvertible {
    public var description: String {
        return String(format: "Requested: %d Began: %d Completed: %d Priority Inc.: %d Priority Dec.: %d Failed: %d Retried: %d", requested, downloadBegan, downloadCompleted, priorityIncreased, priorityDecreased, failed, retried)
    }
}

/// Public API for Asset Manager. Combines all the smaller pieces of the API.
/// Generally you should only use this API, aside from setting up the system.
/// Default implementation uses:
///  - 1 Priority Queue (with priority Web Processor) and 1 normal queue (with normal Web Processor).
///  - Weighted Mirror Policy (going from Mirror to Mirror, before retrying last one 3 times).
public class AssetManager {
    
    private struct Observer {
        private(set) weak var instance: AssetManagerObserver?
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
    
    public let progress = AssetDownloadProgress()
    
    public private(set) var metrics = AssetManagerMetrics()
    
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
    public func request(assets: [AssetFile]) -> [Downloadable] {
        return request(assets: assets, options: RequestOptions())
    }
    
    @discardableResult
    public func request(assets: [AssetFile], options: RequestOptions) -> [Downloadable] {
        
        let uniqueAssets = assets.unique(\.id)
        
        os_log(.info, log: log, "Requested assets: %@", uniqueAssets.map({ $0.id }).joined(separator: ", "))
        
        // Grab Assets we need from file manager, filtering out those that are already downloaded.
        let downloads = cache.requestDownloads(assets: uniqueAssets, options: options)
        
        metrics.requested += uniqueAssets.count
        metrics.downloadBegan += downloads.count
        
        guard downloads.count > 0 else {
            return []
        }
        
        // We need to filter the downloads that are in progress, since there's not much we will do
        // in that case. For those that are in queue, we might move them to a higher priority queue.
        let finalDownloads = downloads.filter { !isDownloading(for: $0.identifier) }
        
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
            
            priorityQueue.download(finalDownloads)
            
            // If those downloads are on download queue and were now moved to priority,
            // we need to cancel them on download, so we do not download them twice.
            let normalQueuedDownloads = finalDownloads.filter { downloadQueue.hasItem(with: $0.identifier) }
            
            downloadQueue.cancel(items: normalQueuedDownloads)
            
            os_log(.info, log: log, "Reprioritising assets: %@", finalDownloads.map({ $0.identifier }).joined(separator: ", "))
        }
        else {
            downloadQueue.download(finalDownloads)
        }
        
        // Add downloads to monitor progresses.
        progress.add(downloadItems: finalDownloads)
        
        os_log(.info, log: log, "[AssetManager]: Metrics on request: %@", metrics.description)
        
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
    
    public func add(observer: AssetManagerObserver) {
        observersQueue.sync {
            self.observers[ObjectIdentifier(observer)] = Observer(instance: observer)
        }
    }
    
    public func remove(observer: AssetManagerObserver) {
        observersQueue.sync {
            self.observers[ObjectIdentifier(observer)] = nil
        }
    }
    
    private func foreachObserver(action: (AssetManagerObserver) -> Void) {
        observers.forEach { $0.value.instance.flatMap(action) }
        
        // cleanup deallocated observer wrappers
        for key in observers.compactMap({ $1.instance == nil ? $0 : nil }) {
            observers[key] = nil
        }
    }
}

// MARK: - DownloadQueueDelegate

extension AssetManager: DownloadQueueDelegate {
    public func downloadQueue(_ queue: DownloadQueue, downloadDidFinish item: Downloadable, to location: URL) {
        do {
            // Move the file to a temporary location, otherwise it gets removed by the system immediately after this function completes
            let tempLocation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-download.tmp")
            try FileManager.default.moveItem(at: location, to: tempLocation)
            
            // store the file to the cache
            processQueue.async {
                self.metrics.downloadCompleted += 1
                autoreleasepool {
                    _ = self.cache.download(item, didFinishTo: tempLocation)
                    self.completeProgress(item: item, with: nil)
                }
            }
            
            os_log(.info, log: log, "[AssetManager]: Metrics on download finished: %@", metrics.description)
        } catch {
            os_log(.error, log: log, "Error moving temporary file: %@", error.localizedDescription)
        }
    }
    
    // Called when download had failed for any reason, including sessions being invalidated.
    public func downloadQueue(_ queue: DownloadQueue, downloadDidFail item: Downloadable, with error: Error) {
        // Check if we should retry, cache will tell us based on it's internal mirror policy.
        // We cannot switch queues here, if it was put on lower priority, it should stay on lower priority.
        if let retryItem = self.cache.download(item, didFailWith: error) {
            // Put it on the same queue.
            metrics.retried += 1
            
            queue.download(retryItem)
        } else {
            metrics.failed += 1
            
            self.completeProgress(item: item, with: error)
        }
        
        os_log(.info, log: log, "[AssetManager]: Metrics on download failed: %@", metrics.description)
    }
    
    private func completeProgress(item: Downloadable, with error: Error?) {
        if let completions = self.assetCompletions[item.identifier] {
            for completion in completions {
                completion(error == nil, item.identifier)
            }
            
            removeAssetCompletion(for: item.identifier)
        }
        
        observersQueue.async {
            if let error = error {
                self.foreachObserver { $0.didFailToDownload(assetId: item.identifier, with: error) }
            } else {
                self.foreachObserver { $0.didFinishDownloading(assetId: item.identifier) }
            }
        }
        
        progress.complete(identifier: item.identifier, with: error)
    }
}

extension AssetManager {
    public func addAssetCompletion(for identifier: String, with completion: @escaping ProgressCompletion) {
        // If this asset is not downloading at all, call the closure immediately!
        guard hasItem(with: identifier) else {
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

extension AssetManager: DownloadQueuable {
    
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
    
    public func hasItem(with identifier: String) -> Bool {
        queues.contains(where: { $0.hasItem(with: identifier) })
    }
    
    public func item(for identifier: String) -> Downloadable? {
        queues.compactMap { $0.item(for: identifier) }.first
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
