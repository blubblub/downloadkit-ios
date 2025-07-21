//
//  RealmMemoryCache.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 23/08/2017.
//  Copyright © 2017 Blub Blub. All rights reserved.
//

import Foundation
import DownloadKitCore
import RealmSwift

/// Will cache resource URL's and images in memory for quick access.
/// URL's are stored in a local dictionary, images are stored in NSCache.
/// Images are stored as `UIImage` or `NSImage`.
/// Note:
/// Cache Manager will load the image into memory after downloading it.
public actor RealmMemoryCache<L: Object>: ResourceRetrievable where L: LocalResourceFile {
    private var resourceURLs = [String: URL]()
    
    private let cache = NSCache<NSString, LocalImage>()
    
    /// Target Realm to update
    let configuration: Realm.Configuration
    
    private var realm: Realm {
        get throws {
            let realm = try Realm(configuration: configuration)
            realm.autorefresh = false
            realm.refresh()
            
            return realm
        }
    }
    
    public init(configuration: Realm.Configuration) {
        self.configuration = configuration
    }
    
    public func fileURL(for id: String) -> URL? {
        if let url = resourceURLs[id] {
            return url
        }
        
        guard let realm = try? self.realm else {
            return nil
        }
        
        autoreleasepool {
            if let localResourceUrl = realm.object(ofType: L.self, forPrimaryKey: id)?.fileURL {
                resourceURLs[id] = localResourceUrl
            }
        }
        
        return resourceURLs[id]
    }
    
    public func image(for id: String) -> LocalImage? {
        if let image = cache.object(forKey: id as NSString) {
            return image
        }
                
        if let url = fileURL(for: id), let data = try? Data(contentsOf: url), let image = LocalImage(data: data) {
            cache.setObject(image, forKey: id as NSString)
            
            return image
        }
        
        return nil
    }
    
    public func data(for id: String) -> Data? {
        if let url = fileURL(for: id) {
            return try? Data(contentsOf: url)
        }
        return nil
    }
    
    public func cleanup(excluding ids: Set<String>) {
        // Clear the cache and resourceURLs except those in urls.
        let resourceURLsCopy = resourceURLs
        
        for (key, _) in resourceURLsCopy {
            if ids.contains(key) {
                continue
            }
            
            resourceURLs.removeValue(forKey: key)
            
            cache.removeObject(forKey: key as NSString)
        }
    }
    
    public func update(for localResource: L) {
        resourceURLs[localResource.id] = localResource.fileURL
    }
}
