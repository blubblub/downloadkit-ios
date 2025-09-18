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

private actor DownloadRequestMap {
    // Track original download requests, so we can retry.
    private(set) var map = [String: [DownloadRequest]]()
    
    func add(_ request: DownloadRequest, for key: String) {
        let identifier = request.id
        
        var existingRequests = map[identifier] ?? []
        
        // If it is the same instance, do not add.
        if existingRequests.contains(where: { $0 === request }) {
            return
        }
        existingRequests.append(request)
        
        map[identifier] = existingRequests
    }
    
    func remove(for identifier: String) {
        map[identifier] = nil
    }
    
    func remove(_ request: DownloadRequest) {
        remove(for: request.id)
    }
    
    func update(request: DownloadRequest, with mirrorSelection: ResourceMirrorSelection) {
        let identifier = request.id
        
        let updatedRequest = DownloadRequest(request, mirror: mirrorSelection)
        add(updatedRequest, for: identifier)
    }
}

public final class RealmCacheManager<L: Object>: ResourceCachable where L: LocalResourceFile {
    public let log = Logger(subsystem: "org.blubblub.downloadkit.realm.cache.manager", category: "Cache")
    
    public let memoryCache: MemoryCache?
    public let localCache: RealmLocalCacheManager<L>
    
    public let mirrorPolicy: MirrorPolicy
    
    private let requestMap = DownloadRequestMap()
    
    public init(configuration: Realm.Configuration,
                mirrorPolicy: MirrorPolicy = WeightedMirrorPolicy()) {
        self.memoryCache = MemoryCache()
        self.localCache = RealmLocalCacheManager<L>(configuration: configuration)
        self.mirrorPolicy = mirrorPolicy
    }
    
    public init(memoryCache: MemoryCache?,
                localCache: RealmLocalCacheManager<L>,
                mirrorPolicy: MirrorPolicy = WeightedMirrorPolicy()) {
        self.memoryCache = memoryCache
        self.localCache = localCache
        self.mirrorPolicy = mirrorPolicy
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
        // Check if resource is available in local cache
        // If downloads() returns empty, it means the resource is already available
        return localCache.downloads(from: [resource], options: RequestOptions()).isEmpty
    }
    
    public func requestDownloads(resources: [ResourceFile], options: RequestOptions) async -> [DownloadRequest] {
        // Update storage for resources that exists.
        let changedResources = localCache.updateStorage(resources: resources, to: options.storagePriority)
        
        if let memoryCache {
            for changedResource in changedResources {
                // Update the memory cache if needed.
                memoryCache.update(fileURL: changedResource.fileURL, for: changedResource.id)
            }
        }

        // Filter out binary and existing resources in local cache.
        let downloadableResources = localCache.downloads(from: resources, options: options)
        
        log.info("Downloading from cache resource count: \(downloadableResources.count)")
        
        var downloadRequests: [DownloadRequest] = []
        
        for resource in downloadableResources {
            guard let mirrorSelection = await mirrorPolicy.mirror(for: resource, lastMirrorSelection: nil, error: nil) else {
                continue
            }
            
            downloadRequests.append(DownloadRequest(resource: resource, options: options, mirror: mirrorSelection))
        }
        
        return downloadRequests
    }
        
    public func downloadRequests(for downloadable: any Downloadable) async -> [DownloadRequest] {
        // Find original request based on mirror ids.
        let downloadableIdentifier = await downloadable.identifier
        let currentRequestMap = await requestMap.map
        
        var originalRequests: [DownloadRequest] = []
        
        for (_, requests) in currentRequestMap {
            for request in requests where request.resource.mirrorIds.contains(downloadableIdentifier) {
                // Append the whole array only once.
                originalRequests.append(contentsOf: requests)
                break
            }
        }
        
        return originalRequests
    }
    
    public func processDownload(_ request: DownloadRequest) async {
        log.info("Download will be processed \(request.id)")
        
        let identifier = request.id
        await requestMap.add(request, for: identifier)
    }
    
    public func download(_ downloadable: any Downloadable, didFinishTo location: URL) async throws -> DownloadRequest? {
        let downloadableIdentifier = await downloadable.identifier
        
        log.debug("Downloadable finished: \(downloadableIdentifier) to: \(location)")
        let requests = await downloadRequests(for: downloadable)
        
        guard requests.count > 0 else {
            log.fault("NO-OP: Received a downloadable without resource information: \(downloadableIdentifier)")
            return nil
        }
        
        let request = requests.first!
        
        do {
            let localObject = try localCache.store(resource: request.resource,
                                                  mirror: request.mirror.mirror,
                                                  at: location,
                                                  options: request.options)
            
            // Update Memory Cache with resource.
            memoryCache?.update(fileURL: localObject.fileURL, for: localObject.id)
            
            for otherRequest in requests {
                await otherRequest.complete()
            }
            
            await requestMap.remove(for: request.id)
        }
        catch {
            await requestMap.remove(for: request.id)
            
            for otherRequest in requests {
                await otherRequest.complete(with: error)
            }
            throw error
        }
        
        // Let mirror policy know that the download completed, so it can clean up after itself.
        await mirrorPolicy.downloadComplete(for: request.resource)
                
        return request
    }
    
    public func download(_ downloadable: any Downloadable, didFailWith error: Error) async -> RetryDownloadRequest? {
        let downloadableIdentifier = await downloadable.identifier
        
        log.debug("Downloadable failed: \(downloadableIdentifier) Error: \(error.localizedDescription)")
        
        let requests = await downloadRequests(for: downloadable)
        
        guard requests.count > 0 else {
            log.fault("NO-OP: Received a downloadable without resource information: \(downloadableIdentifier)")
            return nil
        }
        
        let request = requests.first!
        
        let identifier = request.id
        
        guard let mirrorSelection = await mirrorPolicy.mirror(for: request.resource,
                                                        lastMirrorSelection: request.mirror,
                                                        error: error) else {
            log.error("Download failed: \(identifier) Error: \(error.localizedDescription)")
            
            // Clear download selection for the identifier.
            
            for otherRequest in requests {
                await otherRequest.complete(with: error)
            }
            
            await requestMap.remove(for: identifier)
            return RetryDownloadRequest(request: request)
        }
        
        let mirrorDownloadableIdentifier = await mirrorSelection.downloadable.identifier
        
        // Update requestMap with new mirror selection.
        await requestMap.update(request: request, with: mirrorSelection)
        
        log.error("Retrying download of: \(identifier) with: \(mirrorDownloadableIdentifier)")
        
        return RetryDownloadRequest(request: request, nextMirror: mirrorSelection)
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
