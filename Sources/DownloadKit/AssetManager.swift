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

public typealias ProgressCompletion = (Bool, String) -> Void

protocol AssetManagerDelegate {
    /// Called when asset is ready for use.
    func assetManager(_ assetManager: AssetManager, assetReady asset: AssetFile)
    
    /// Called when a transfer had failed through all retry logic and there is no practical way
    /// to get it.
    func assetManager(_ assetManager: AssetManager, assetUnavailable asset: AssetFile, error: Error)
}

public enum DownloadPriority {
    case normal
    case high
    case userInteractive
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
}

/// Public API for Asset Manager. Combines all the smaller pieces of the API.
/// Generally you should only use this API, aside from setting up the system.
/// Default implementation uses:
///  - 1 Priority Queue (with priority Web Processor) and 1 normal queue (with normal Web Processor).
///  - Weighted Mirror Policy (going from Mirror to Mirror, before retrying last one 3 times).
public class AssetManager {
    
    // MARK: - Private Properties
    
    private var assetCompletions: [String: [ProgressCompletion]] = [:]

    // MARK: - Public Properties
    public var log: OSLog = logDK
        
    public let downloadQueue: DownloadQueue
    public let priorityQueue: DownloadQueue?
    
    public let cache: AssetCacheable
    
    public let progress = AssetDownloadProgress()
    
    public convenience init(cache: AssetCacheable) {
        let downloadQueue = DownloadQueue()
        downloadQueue.add(processor: WebDownloadProcessor())
        
        let priorityQueue = DownloadQueue()
        priorityQueue.add(processor: WebDownloadProcessor.priorityProcessor())
        priorityQueue.simultaneousDownloads = 10
        
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
    
    public func request(assets: [AssetFile]) {
        request(assets: assets, options: RequestOptions())
    }
    
    public func request(assets: [AssetFile], options: RequestOptions) {
        // Grab Assets we need from file manager, filtering out those that are already downloaded.
        let downloads = cache.requestDownloads(assets: assets, options: options)
        
        guard downloads.count > 0 else {
            log.info("No assets need to be transferred at this point, all are available locally.")
            
            return
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
            
            downloadQueue.download(currentPriorityDownloads)
            
            priorityQueue.download(finalDownloads)
            
            // If those downloads are on download queue and were now moved to priority,
            // we need to cancel them on download, so we do not download them twice.
            
            let normalQueuedDownloads = finalDownloads.filter { downloadQueue.hasItem(with: $0.identifier) }
            
            downloadQueue.cancel(items: normalQueuedDownloads)
        }
        else {
            downloadQueue.download(finalDownloads)
        }
        
        // Add downloads to monitor progresses.
        progress.add(downloadItems: finalDownloads)
    }
    
    public func resume(completion: (() -> Void)? = nil) {
        
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
        downloadQueue.cancelAll()
        priorityQueue?.cancelAll()
        
        for (identifier, completions) in assetCompletions {
            for completion in completions {
                completion(false, identifier)
            }
        }
        
        assetCompletions.removeAll()
    }
}

// MARK: - DownloadQueueDelegate

extension AssetManager: DownloadQueueDelegate {
    public func downloadQueue(_ queue: DownloadQueue, downloadDidFinish item: Downloadable, to location: URL) {
        // Cache will store the file, since it has completed downloading. This operation needs to be sync.
        // We should be on background thread here already.
        _ = cache.download(downloadable: item, didFinishTo: location)
        completeProgress(item: item, with: nil)
    }
    
    // Called when download had failed for any reason, including sessions being invalidated.
    public func downloadQueue(_ queue: DownloadQueue, downloadDidFail item: Downloadable, with error: Error) {
        // Check if we should retry, cache will tell us based on it's internal mirror policy.
        // We cannot switch queues here, if it was put on lower priority, it should stay on lower priority.
        //        
        if let retryItem = cache.download(downloadable: item, didFailWith: error) {
            // Put it on the same queue.
            queue.download(retryItem)
        }
        else {
            completeProgress(item: item, with: error)
        }
    }
    
    private func completeProgress(item: Downloadable, with error: Error?) {
        if let completions = self.assetCompletions[item.identifier] {
            for completion in completions {
                completion(false, item.identifier)
            }
            
            self.assetCompletions[item.identifier] = nil
        }
        
        progress.complete(identifier: item.identifier, with: error)
    }
}

extension AssetManager {
    public func addAssetCompletion(for identifier: String, with completion: @escaping ProgressCompletion) {
        // If this asset is not downloading at all, call the closure immediately!
        
        guard !downloadQueue.hasItem(with: identifier) && !(priorityQueue?.hasItem(with: identifier) ?? false) else {
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
            return downloadQueue.isActive && (priorityQueue?.isActive ?? true)
        }
        set {
            downloadQueue.isActive = newValue
            priorityQueue?.isActive = newValue
        }
    }
    
    public var currentDownloadCount: Int {
        downloadQueue.currentDownloads.count + (priorityQueue?.currentDownloads.count ?? 0)
    }
    
    public var queuedDownloadCount: Int {
        downloadQueue.queuedDownloads.count + (priorityQueue?.queuedDownloads.count ?? 0)
    }
    
    public var downloads: [Downloadable] {
        (priorityQueue?.downloads ?? []) + downloadQueue.downloads
    }
    
    public var currentDownloads: [Downloadable] {
        (priorityQueue?.currentDownloads ?? []) + downloadQueue.currentDownloads
    }
    
    public var queuedDownloads: [Downloadable] {
        (priorityQueue?.queuedDownloads ?? []) + downloadQueue.queuedDownloads
    }
    
    public func hasItem(with identifier: String) -> Bool {
        return (priorityQueue?.hasItem(with: identifier) ?? false) || downloadQueue.hasItem(with: identifier)
    }
    
    public func item(for identifier: String) -> Downloadable? {
        if let item = priorityQueue?.item(for: identifier) {
            return item
        }
        
        return downloadQueue.item(for: identifier)
    }
    
    public func isDownloading(for identifier: String) -> Bool {
        return (priorityQueue?.isDownloading(for: identifier) ?? false) || downloadQueue.isDownloading(for: identifier)
    }
}
