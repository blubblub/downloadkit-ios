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
}

public class RealmCacheManager<L: Object>: AssetCacheable where L: LocalAssetFile {
    
    public var log: OSLog = logDK
    
    public var memoryCache: RealmMemoryCache<L>?
    public let localCache: RealmLocalCacheManager<L>
    public var mirrorPolicy: MirrorPolicy = WeightedMirrorPolicy()
    
    private var downloadableMap = AtomicDictionary<String, DownloadSelection>()
    
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
    
    public func requestDownloads(assets: [AssetFile], options: RequestOptions) -> [Downloadable] {
        // Update storage for assets that exists.
        localCache.updateStorage(assets: assets, to: options.storagePriority)
        
        // Filter out binary and existing assets in local asset.
        let downloadableAssets = localCache.downloads(from: assets, options: options)
            
        let downloadSelections: [DownloadSelection] = downloadableAssets.compactMap { asset in
            guard let mirrorSelection = mirrorPolicy.mirror(for: asset, lastMirrorSelection: nil, error: nil) else {
                return nil
            }
            
            return DownloadSelection(id: asset.id,
                                     options: options,
                                     asset: asset,
                                     mirror: mirrorSelection)
        }
        
        downloadSelections.forEach {
            downloadableMap[$0.mirror.downloadable.identifier] = $0
        }
        
        return downloadSelections.map { $0.mirror.downloadable }
    }
    
    public func download(_ downloadable: Downloadable, didFinishTo location: URL) -> LocalAssetFile? {
        defer {
            downloadableMap[downloadable.identifier] = nil
        }

        guard let downloadSelection = downloadableMap[downloadable.identifier] else {
            os_log(.fault, log: log, "[RealmCacheManager]: NO-OP: Received a downloadable without asset information: %@", downloadable.description)
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
            os_log(.error, log: log, "[RealmCacheManager]: Unable to cache file: %@", downloadable.description)
            
            return nil
        }
    }
    
    public func download(_ downloadable: Downloadable, didFailWith error: Error) -> Downloadable? {
        guard let downloadSelection = downloadableMap[downloadable.identifier] else {
            os_log(.fault, log: log, "[RealmCacheManager]: NO-OP: Received a downloadable without asset information: %@", downloadable.description)
            return nil
        }
        
        guard let mirrorSelection = mirrorPolicy.mirror(for: downloadSelection.asset,
                                                        lastMirrorSelection: downloadSelection.mirror,
                                                        error: error) else {
            os_log(.error, log: log, "[RealmCacheManager]: Download failed: %@ Error: %@",
                   downloadable.description, error.localizedDescription)
            downloadableMap[downloadable.identifier] = nil
            return nil
        }
        
        os_log(.error, log: log, "[RealmCacheManager]: Retrying download with: %@", mirrorSelection.downloadable.description)
        
        downloadableMap[downloadable.identifier]?.mirror = mirrorSelection

        return mirrorSelection.downloadable
    }
    
    public func cleanup(excluding urls: Set<URL>) {
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
