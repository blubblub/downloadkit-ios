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

public final class RealmMemoryCache<L: Object>: @unchecked Sendable, ResourceRetrievable where L: LocalResourceFile {
    private let urlCache = NSCache<NSString, NSURL>()
    
    private let imageCache = NSCache<NSString, LocalImage>()
    
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
        if let url = urlCache.object(forKey: id as NSString) {
            return url as URL
        }
        
        guard let realm = try? self.realm else {
            return nil
        }
        
        autoreleasepool {
            if let localResourceUrl = realm.object(ofType: L.self, forPrimaryKey: id)?.fileURL {
                urlCache.setObject(localResourceUrl as NSURL, forKey: id as NSString)
            }
        }
        
        return urlCache.object(forKey: id as NSString) as? URL
    }
    
    public func image(for id: String) -> LocalImage? {
        if let image = imageCache.object(forKey: id as NSString) {
            return image
        }
                
        if let url = fileURL(for: id), let data = try? Data(contentsOf: url), let image = LocalImage(data: data) {
            imageCache.setObject(image, forKey: id as NSString)
            
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
    
    public func update(for localResource: L) {
        urlCache.setObject(localResource.fileURL as NSURL, forKey: localResource.id as NSString)
    }
}
