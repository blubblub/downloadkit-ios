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

public actor RealmCacheManager<L: Object>: ResourceCachable where L: LocalResourceFile {
       
    public let log = Logger(subsystem: "org.blubblub.downloadkit.realm.cache.manager", category: "Cache")
    
    public let memoryCache: RealmMemoryCache<L>?
    public let localCache: RealmLocalCacheManager<L>
    
    public var mirrorPolicy: MirrorPolicy = WeightedMirrorPolicy()
    
    // Track original download requests, so we can retry.
    private var requestMap = [String: DownloadRequest]()
    
    public init(configuration: Realm.Configuration,
                mirrorPolicy: MirrorPolicy = WeightedMirrorPolicy()) {
        self.memoryCache = RealmMemoryCache<L>(configuration: configuration)
        self.localCache = RealmLocalCacheManager<L>(configuration: configuration)
        self.mirrorPolicy = mirrorPolicy
    }
    
    public init(memoryCache: RealmMemoryCache<L>?,
                localCache: RealmLocalCacheManager<L>,
                mirrorPolicy: MirrorPolicy = WeightedMirrorPolicy()) {
        self.memoryCache = memoryCache
        self.localCache = localCache
        self.mirrorPolicy = mirrorPolicy
    }
    
    // MARK: - ResourceCachable
    public func requestDownloads(resources: [ResourceFile], options: RequestOptions) async -> [DownloadRequest] {
        // Update storage for resources that exists.
        let changedResources = localCache.updateStorage(resources: resources, to: options.storagePriority)
        
        for changedResource in changedResources {
            await memoryCache?.update(for: changedResource)
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
        
        for request in downloadRequests {
            let idenitifier = request.resourceId
            requestMap[idenitifier] = request
        }
        
        return downloadRequests
    }
    
    public func downloadRequest(for downloadable: any Downloadable) async -> DownloadRequest? {
        // Find original request based on mirror ids.
        let downloadableIdentifier = await downloadable.identifier
        
        for (_, request) in requestMap {
            if request.resource.mirrorIds.contains(downloadableIdentifier) {
                return request
            }
        }
        
        return nil
    }
    
    public func download(_ downloadable: any Downloadable, didFinishTo location: URL) async throws -> DownloadRequest? {
        let downloadableIdentifier = await downloadable.identifier
        
        log.debug("Downloadable finished: \(downloadableIdentifier) to: \(location)")
        
        guard let request = await downloadRequest(for: downloadable) else {
            log.fault("NO-OP: Received a downloadable without resource information: \(downloadableIdentifier)")
            return nil
        }
        
        do {
            let localObject = try localCache.store(resource: request.resource,
                                                  mirror: request.mirror.mirror,
                                                  at: location,
                                                  options: request.options)
            
            // Update Memory Cache with resource.
            await memoryCache?.update(for: localObject)
            await request.complete()
            requestMap[request.resourceId] = nil
        }
        catch {
            requestMap[request.resourceId] = nil
            await request.complete(with: error)
            throw error
        }
        
        // Let mirror policy know that the download completed, so it can clean up after itself.
        await mirrorPolicy.downloadComplete(for: request.resource)
                
        return request
    }
    
    public func download(_ downloadable: any Downloadable, didFailWith error: Error) async -> RetryDownloadRequest? {
        let downloadableIdentifier = await downloadable.identifier
        
        log.debug("Downloadable failed: \(downloadableIdentifier) Error: \(error.localizedDescription)")
        
        guard let request = await downloadRequest(for: downloadable) else {
            log.fault("NO-OP: Received a downloadable without resource information: \(downloadableIdentifier)")
            return nil
        }
        
        let identifier = request.resourceId
        
        guard let mirrorSelection = await mirrorPolicy.mirror(for: request.resource,
                                                        lastMirrorSelection: request.mirror,
                                                        error: error) else {
            log.error("Download failed: \(identifier) Error: \(error.localizedDescription)")
            
            // Clear download selection for the identifier.
            await request.complete(with: error)
            
            requestMap[identifier] = nil
            
            return RetryDownloadRequest(request: request)
        }
        
        let mirrorDownloadableIdentifier = await mirrorSelection.downloadable.identifier
        
        log.error("Retrying download of: \(identifier) with: \(mirrorDownloadableIdentifier)")
        
        return RetryDownloadRequest(request: request, nextMirror: mirrorSelection)
    }
    
    public func cleanup(excluding urls: Set<URL>) {
        do {
            try localCache.cleanup(excluding: urls)
        }
        catch let error {
            log.error("Error Cleaning up: \(error.localizedDescription)")
        }
    }
    
    // MARK: - ResourceFileCacheable
    
    public subscript(id: String) -> URL? {
        get async {
            return await memoryCache?[id]
        }
    }
    
    public func resourceImage(url: URL) async -> LocalImage? {
        return await memoryCache?.resourceImage(url: url)
    }
}
