//
//  RealmCacheManager.swift
//  
//
//  Created by Dal Rupnik on 2/11/21.
//

import Foundation
import RealmSwift
import os.log

public class RealmCacheManager<L: Object>: AssetCacheable where L: LocalResourceFile {
    
        
    public var log: OSLog = logDK
    
    public var memoryCache: RealmMemoryCache<L>?
    public let localCache: RealmLocalCacheManager<L>
    public var mirrorPolicy: MirrorPolicy = WeightedMirrorPolicy()
    
    private var downloadableMap = AtomicDictionary<String, DownloadRequest>()
    
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
    
    // MARK: - AssetCachable
    public func requestDownloads(assets: [ResourceFile], options: RequestOptions) -> [DownloadRequest] {
        // Update storage for assets that exists.
        localCache.updateStorage(assets: assets, to: options.storagePriority)
        
        // Filter out binary and existing assets in local asset.
        let downloadableAssets = localCache.downloads(from: assets, options: options)
        
        os_log(.info, log: log, "Downloading from cache asset count: %d", downloadableAssets.count)
        
        let downloadRequests: [DownloadRequest] = downloadableAssets.compactMap { asset in
            guard let mirrorSelection = mirrorPolicy.mirror(for: asset, lastMirrorSelection: nil, error: nil) else {
                return nil
            }
            
            return DownloadRequest(asset: asset, options: options, mirror: mirrorSelection)
        }
        
        downloadRequests.forEach {
            downloadableMap[$0.downloadableIdentifier] = $0
        }
        
        return downloadRequests
    }
    
    public func downloadRequest(for downloadable: Downloadable) -> DownloadRequest? {
        return downloadableMap[downloadable.identifier]
    }
    
    public func download(_ downloadable: Downloadable, didFinishTo location: URL) throws -> DownloadRequest? {
        defer {
            downloadableMap[downloadable.identifier] = nil
        }

        guard let downloadRequest = downloadableMap[downloadable.identifier] else {
            os_log(.fault, log: log, "[RealmCacheManager]: NO-OP: Received a downloadable without asset information: %@", downloadable.description)
            return nil
        }
        
        _ = try localCache.store(asset: downloadRequest.asset,
                                              mirror: downloadRequest.mirror.mirror,
                                              at: location,
                                              options: downloadRequest.options)
        
        // Let mirror policy know that the download completed, so it can clean up after itself.
        mirrorPolicy.downloadComplete(for: downloadRequest.asset)
        
        return downloadRequest
    }
    
    public func download(_ downloadable: Downloadable, didFailWith error: Error) -> RetryDownloadRequest? {

        guard let downloadRequest = downloadableMap[downloadable.identifier] else {
            os_log(.fault, log: log, "[RealmCacheManager]: NO-OP: Received a downloadable without asset information: %@", downloadable.description)
            return nil
        }
        
        // Clear download selection for the identifier.
        downloadableMap[downloadable.identifier] = nil
        
        guard let mirrorSelection = mirrorPolicy.mirror(for: downloadRequest.asset,
                                                        lastMirrorSelection: downloadRequest.mirror,
                                                        error: error) else {
            os_log(.error, log: log, "[RealmCacheManager]: Download failed: %@ Error: %@",
                   downloadable.description, error.localizedDescription)
            
            return RetryDownloadRequest(retryRequest: nil, originalRequest: downloadRequest)
        }
        
        os_log(.error, log: log, "[RealmCacheManager]: Retrying download of: %@ with: %@", downloadable.description, mirrorSelection.downloadable.description)
        
        let retryDownloadRequest = DownloadRequest(asset: downloadRequest.asset, options: downloadRequest.options, mirror: mirrorSelection)
        
        // Write it to downloadable map with new download selection
        downloadableMap[retryDownloadRequest.downloadableIdentifier] = retryDownloadRequest

        return RetryDownloadRequest(retryRequest: retryDownloadRequest, originalRequest: downloadRequest)
    }
    
    public func cleanup(excluding urls: Set<URL>) {
        do {
            try localCache.cleanup(excluding: urls)
        }
        catch let error {
            os_log(.error, log: log, "[RealmCacheManager]: Error Cleaning up: %@", error.localizedDescription)
        }
    }
    
    // MARK: - AssetFileCacheable
    
    public subscript(id: String) -> URL? {
        return memoryCache?[id]
    }
    
    public func assetImage(url: URL) -> LocalImage? {
        return memoryCache?.assetImage(url: url)
    }
}
