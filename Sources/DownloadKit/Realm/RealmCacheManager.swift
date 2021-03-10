//
//  RealmCacheManager.swift
//  
//
//  Created by Dal Rupnik on 2/11/21.
//

import Foundation
import RealmSwift
import os.log

/// Hold references to downloads, so they can be properly handled.
private struct DownloadSelection: Identifiable {
    let id: String
    let options: RequestOptions
    let asset: AssetFile
    var mirror: AssetMirrorSelection
    var downloadable: Downloadable
}

public class RealmCacheManager<L: Object>: AssetCacheable where L: LocalAssetFile {
    
    public var log: OSLog = logDK
    
    public var memoryCache: RealmMemoryCache? = RealmMemoryCache<L>()
    public var localCache = RealmLocalCacheManager<L>()
    public var mirrorPolicy: MirrorPolicy = WeightedMirrorPolicy()
    
    @Atomic private var downloadableMap: [String: DownloadSelection] = [:]
    
    public var configuration: Realm.Configuration = Realm.Configuration.defaultConfiguration {
        didSet {
            memoryCache?.configuration = configuration
            localCache.configuration = configuration
        }
    }
    
    public init(memoryCache: RealmMemoryCache<L>? = RealmMemoryCache(),
                localCache: RealmLocalCacheManager<L> = RealmLocalCacheManager(),
                mirrorPolicy: MirrorPolicy = WeightedMirrorPolicy()) {
        self.memoryCache = memoryCache
        self.localCache = localCache
        self.mirrorPolicy = mirrorPolicy
    }
        
    public func requestDownloads(assets: [AssetFile], options: RequestOptions) -> [Downloadable] {
        // Update storage for assets that exists.
        localCache.updateStorage(assets: assets, to: options.storagePriority)
        
        // Filter out binary and existing assets in local asset.
        let downloadableAssets = localCache.requestDownloads(assets: assets, options: options)
            
        let downloadSelections: [DownloadSelection] = downloadableAssets.compactMap { asset in
            guard let mirrorSelection = mirrorPolicy.mirror(for: asset, lastMirrorSelection: nil, error: nil) else {
                return nil
            }
            
            return DownloadSelection(id: asset.id, options: options, asset: asset, mirror: mirrorSelection, downloadable: mirrorSelection.downloadable)
        }
        
        return downloadSelections.map { $0.downloadable }
    }
    
    public func download(downloadable: Downloadable, didFinishTo location: URL) -> LocalAssetFile? {
        defer {
            downloadableMap[downloadable.identifier] = nil
        }
        
        guard let downloadSelection = downloadableMap[downloadable.identifier] else {
            log.fault("[RealmCacheManager]: NO-OP: Received a downloadable without asset information: %@", downloadable.description)
            return nil
        }
        
        do {
            let localAsset = try localCache.store(asset: downloadSelection.asset,
                                                  mirror: downloadSelection.mirror.mirror,
                                                  at: location,
                                                  options: downloadSelection.options)
            
            // Let mirror policy know that the download completed, so it can clean up after itself.
            mirrorPolicy.downloadComplete(for: downloadSelection.asset)
            
            return localAsset
        }
        catch {
            log.error("[RealmCacheManager]: Unable to cache file: %@", downloadable.description)
            
            return nil
        }
    }
    
    public func download(downloadable: Downloadable, didFailWith error: Error) -> Downloadable? {
        guard let downloadSelection = downloadableMap[downloadable.identifier] else {
            log.fault("[RealmCacheManager]: NO-OP: Received a downloadable without asset information: %@", downloadable.description)
            return nil
        }
        
        guard let mirrorSelection = mirrorPolicy.mirror(for: downloadSelection.asset, mirrorSelection: downloadSelection.mirror, error: error) else {
            log.info("[RealmCacheManager]: Download failed: %@ Error: %@ No more retries.", downloadable.description)
            downloadableMap[downloadable.identifier] = nil
            return nil
        }
        
        log.info("[RealmCacheManager]: Download failed: %@ Error: %@ Retrying with: %@", downloadable.description, mirrorSelection.downloadable.description)
        
        downloadableMap[downloadable.identifier]?.mirror = mirrorSelection

        return mirrorSelection.downloadable
    }
    
    public func cleanup(excluding urls: [URL]) {
        localCache.cleanup(excluding: urls)
    }
    
    // MARK: - AssetFileCacheable
    
    public subscript(id: String) -> URL? {
        return memoryCache?[id]
    }
    
    public func assetImage(url: URL) -> LocalImage? {
        return memoryCache?.assetImage(url: url)
    }
}
