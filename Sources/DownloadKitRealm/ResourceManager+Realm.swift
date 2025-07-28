//
//  ResourceManager+Realm.swift
//  DownloadKit
//
//  Created by Dal Rupnik on 01.07.2025.
//

import RealmSwift
import DownloadKitCore

public extension ResourceManager {
    static func `default`(with configuration: Realm.Configuration = .defaultConfiguration) async -> ResourceManager {
        let cache = RealmCacheManager<CachedLocalFile>(memoryCache: MemoryCache(), localCache: RealmLocalCacheManager(configuration: configuration))
        
        let downloadQueue = DownloadQueue()
        await downloadQueue.add(processor: WebDownloadProcessor())
        
        let resourceManager = ResourceManager(cache: cache, downloadQueue: downloadQueue)
                
        return resourceManager
    }    
}
