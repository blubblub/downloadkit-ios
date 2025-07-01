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
    
    private var downloadableMap = [String: DownloadRequest]()
    
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
        localCache.updateStorage(resources: resources, to: options.storagePriority) { [weak self] resource in
            guard let self = self else { return }
            Task {
                await self.memoryCache?.update(for: resource)
            }
        }

        // Filter out binary and existing resources in local cache.
        let downloadableResources = localCache.downloads(from: resources, options: options)
        
        log.info("Downloading from cache resource count: \(downloadableResources.count)")
        
        let downloadRequests: [DownloadRequest] = downloadableResources.compactMap { resource in
            guard let mirrorSelection = mirrorPolicy.mirror(for: resource, lastMirrorSelection: nil, error: nil) else {
                return nil
            }
            
            return DownloadRequest(resource: resource, options: options, mirror: mirrorSelection)
        }
        
        for request in downloadRequests {
            let downloadIdentifier = await request.downloadableIdentifier()
            downloadableMap[downloadIdentifier] = request
        }
        
        return downloadRequests
    }
    
    public func downloadRequest(for downloadable: Downloadable) async -> DownloadRequest? {
        return await downloadableMap[downloadable.identifier]
    }
    
    public func download(_ downloadable: Downloadable, didFinishTo location: URL) async throws -> DownloadRequest? {

        let identifier = await downloadable.identifier
        
        guard let downloadRequest = self.downloadableMap[identifier] else {
            log.fault("NO-OP: Received a downloadable without resource information: \(identifier)")
            return nil
        }
        
        do {
            _ = try localCache.store(resource: downloadRequest.resource,
                                                  mirror: downloadRequest.mirror.mirror,
                                                  at: location,
                                                  options: downloadRequest.options)
            downloadableMap[identifier] = nil
        }
        catch {
            downloadableMap[identifier] = nil
            throw error
        }
        
        // Let mirror policy know that the download completed, so it can clean up after itself.
        mirrorPolicy.downloadComplete(for: downloadRequest.resource)
                
        return downloadRequest
    }
    
    public func download(_ downloadable: Downloadable, didFailWith error: Error) async -> RetryDownloadRequest? {

        let identifier = await downloadable.identifier
        
        guard let downloadRequest = downloadableMap[identifier] else {
            log.fault("NO-OP: Received a downloadable without resource information: \(identifier)")
            return nil
        }
        
        // Clear download selection for the identifier.
        downloadableMap[identifier] = nil
        
        guard let mirrorSelection = mirrorPolicy.mirror(for: downloadRequest.resource,
                                                        lastMirrorSelection: downloadRequest.mirror,
                                                        error: error) else {
            log.error("Download failed: \(identifier) Error: \(error.localizedDescription)")
            
            return RetryDownloadRequest(retryRequest: nil, originalRequest: downloadRequest)
        }
        
        let downloadableIdentifier = await mirrorSelection.downloadable.identifier
        
        log.error("Retrying download of: \(identifier) with: \(downloadableIdentifier)")
        
        let retryDownloadRequest = DownloadRequest(resource: downloadRequest.resource, options: downloadRequest.options, mirror: mirrorSelection)
        
        // Write it to downloadable map with new download selection
        let newDownloadIdentifier = await retryDownloadRequest.downloadableIdentifier()
        downloadableMap[newDownloadIdentifier] = retryDownloadRequest

        return RetryDownloadRequest(retryRequest: retryDownloadRequest, originalRequest: downloadRequest)
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
