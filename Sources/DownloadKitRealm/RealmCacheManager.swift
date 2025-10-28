//
//  RealmCacheManager.swift
//  
//
//  Created by Dal Rupnik on 2/11/21.
//

import Foundation
import DownloadKitCore
import RealmSwift
import os.log

private actor DownloadTaskMap {
    // Track original download requests, so we can retry.
    private var map = [String: [DownloadTask]]()
        
    func addIfNeeded(_ task: DownloadTask) -> Bool {
        let isInMap = contains(task.id)
        add(task)
        
        return isInMap
    }
    
    func tasks(for identifier: String) -> [DownloadTask] {
        return map[identifier] ?? []
    }
    
    func completeAll(for identifier: String, error: Error? = nil) async {
        for other in map[identifier] ?? [] {
            await other.complete(with: error)
        }
        
        map[identifier] = nil
    }
        
    private func contains(_ identifier: String) -> Bool {
        return map[identifier] != nil
    }
    
    private func add(_ task: DownloadTask) {
        let identifier = task.id
        
        var existingTasks = map[identifier] ?? []
        
        // If it is the same instance, do not add.
        if existingTasks.contains(where: { $0 === task }) {
            return
        }
        existingTasks.append(task)
        
        map[identifier] = existingTasks
    }
}

public final class RealmCacheManager<L: Object>: ResourceCachable where L: LocalResourceFile {

    
    public let log = Logger(subsystem: "org.blubblub.downloadkit.realm.cache.manager", category: "Cache")
    
    public let memoryCache: MemoryCache?
    public let localCache: RealmLocalCacheManager<L>
    
    private let taskMap = DownloadTaskMap()
    
    public init(configuration: Realm.Configuration) {
        self.memoryCache = MemoryCache()
        self.localCache = RealmLocalCacheManager<L>(configuration: configuration)
    }
    
    public init(memoryCache: MemoryCache?,
                localCache: RealmLocalCacheManager<L>) {
        self.memoryCache = memoryCache
        self.localCache = localCache
    }
    
    // MARK: - ResourceCachable
    
    public func image(for resourceId: String) -> LocalImage? {
        do {
            if let memory = memoryCache, let image = memory.image(for: resourceId) {
                return image
            }
            else if let url = localCache.fileURL(for: resourceId) {
                let data = try Data(contentsOf: url)
                let image = LocalImage(data: data)
                
                if let memoryCache, let image {
                    memoryCache.update(image: image, for: resourceId)
                }
                return image
            }
        }
        catch let error {
            log.error("Error reading file id: \(resourceId): \(error)")
        }
        
        return nil
    }
    
    public func data(for id: String) -> Data? {
        guard let fileUrl = fileURL(for: id) else {
            return nil
        }
        
        return try? Data(contentsOf: fileUrl)
    }
    
    public func fileURL(for resourceId: String) -> URL? {
        // Return from Memory, if available.
        if let memory = memoryCache, let fileUrl = memory.fileURL(for: resourceId) {
            return fileUrl
        }
        
        // If memory does not have the URL, try fetching it and storing it back to memory as well.
        let cachedResourceURL = localCache.fileURL(for: resourceId)
        
        if let memoryCache, let cachedResourceURL {
            memoryCache.update(fileURL: cachedResourceURL, for: resourceId)
        }
        
        return cachedResourceURL
    }
    
    public func isAvailable(resource: ResourceFile) -> Bool {
        return fileURL(for: resource.id) != nil
    }
    
    public func requestDownloads(resources: [ResourceFile], options: RequestOptions) async -> [DownloadRequest] {
    
        // Filter out binary and existing resources in local cache.
        let downloadableResources = localCache.downloads(from: resources)
        
        log.info("Downloading from cache resource count: \(downloadableResources.count)")
        
        var downloadRequests: [DownloadRequest] = []
        
        for resource in downloadableResources {
            downloadRequests.append(DownloadRequest(resource: resource, options: options))
        }
        
        return downloadRequests
    }
        
    public func downloads(for downloadTask: DownloadTask) async -> [DownloadTask] {
        // Find original request based on mirror ids.
        return await taskMap.tasks(for: downloadTask.id)
    }
    
    public func updateStorage(resources: [any ResourceFile], storage: StoragePriority) {
        log.info("Updating storage for: \(resources.map(\.id)) to: \(storage.rawValue)")
        // Update storage for resources that exists.
        let changedResources = localCache.updateStorage(resources: resources, to: storage)
        
        if let memoryCache {
            for changedResource in changedResources {
                // Update the memory cache if needed.
                memoryCache.update(fileURL: changedResource.fileURL, for: changedResource.id)
            }
        }
    }
    
    public func download(startProcessing downloadTask: DownloadTask) async -> DownloadProcessingState {
        if isAvailable(resource: downloadTask.request.resource) {
            log.debug("Request is already available, will complete the request: \(downloadTask.id)")
            
            await downloadTask.complete()
            return DownloadProcessingState(isFinished: true, isDownloading: false)
        }
        
        // Check if resource is available. Request could have been created earlier.
        let isInRequestMap = await taskMap.addIfNeeded(downloadTask)
        
        if isInRequestMap {
            log.debug("Request already exists in map, logging request, but denying download: \(downloadTask.id)")
        }
        
        return DownloadProcessingState(isFinished: false, isDownloading: isInRequestMap)
    }
    
    public func download(_ downloadTask: DownloadTask, downloadable: Downloadable, didFinishTo location: URL) async throws {
        
        log.debug("Download task finished: \(downloadTask.id) to: \(location)")
        let downloads = await downloads(for: downloadTask)
        
        do {
            let localObject = try localCache.store(resource: downloadTask.request.resource, mirrorId: await downloadable.identifier, at: location, options: downloadTask.request.options)
            
            // Update Memory Cache with resource.
            memoryCache?.update(fileURL: localObject.fileURL, for: localObject.id)
            
            log.debug("Cache stored downloaded file request: \(downloadTask.id) count: \(downloads.count)")
            
            await taskMap.completeAll(for: downloadTask.id)
        }
        catch {
            log.error("Error storing downloaded file: \(error.localizedDescription) request: \(downloadTask.id) count: \(downloads.count)")
            
            await taskMap.completeAll(for: downloadTask.id, error: error)
            
            throw error
        }
    }
    
    public func download(_ downloadTask: DownloadTask, didFailWith error: any Error) async {
        log.error("Download task failed: \(downloadTask.id) error: \(error)")

        await taskMap.completeAll(for: downloadTask.id, error: error)
    }
        
    public func cleanup(excluding ids: Set<String>) {
        do {
            try localCache.cleanup(excluding: ids)
        }
        catch let error {
            log.error("Error Cleaning up: \(error.localizedDescription)")
        }
    }
}
