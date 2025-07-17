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
public actor RealmMemoryCache<L: Object>: ResourceFileCacheable where L: LocalResourceFile {
    private var resourceURLs = [String: URL]()
    
    private let cache = NSCache<NSURL, LocalImage>()
    
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
    
    public subscript(id: String) -> URL? {
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
    
    public func resourceImage(url: URL) -> LocalImage? {
        if let image = cache.object(forKey: url as NSURL) {
            return image
        }
        
        if let data = try? Data(contentsOf: url), let image = LocalImage(data: data) {
            cache.setObject(image, forKey: url as NSURL)
            
            return image
        }
        
        return nil
    }
    
    public func update(for localResource: L) {
        resourceURLs[localResource.id] = localResource.fileURL
    }
}
