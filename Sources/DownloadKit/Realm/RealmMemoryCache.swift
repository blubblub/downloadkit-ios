//
//  AssetCache.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 23/08/2017.
//  Copyright © 2017 Blub Blub. All rights reserved.
//

import Foundation
import RealmSwift

#if canImport(UIKit)
import UIKit
#endif

#if os(OSX)
import AppKit
public typealias LocalImage = NSImage
#else
public typealias LocalImage = UIImage
#endif


public protocol AssetFileCacheable {
    subscript(id: String) -> URL? { get }
    func assetImage(url: URL) -> LocalImage?
}

/// Will cache asset URL's and images in memory for quick access.
/// URL's are stored in a local dictionary, images are stored in NSCache.
/// Images are stored as `UIImage`
/// Note:
/// Cache Manager will load the image into memory after downloading it.
public class RealmMemoryCache<L: Object>: AssetFileCacheable where L: LocalAssetFile {
    private var cacheQueue = DispatchQueue(label: "org.blubblub.downloadkit.memorycache.queue")
    private var _assetURLs = [String: URL]()
    private var assetURLs: [String: URL] {
        get {
            return cacheQueue.sync {
                return _assetURLs
            }
        }
        set {
            cacheQueue.sync {
                _assetURLs = newValue
            }
        }
    }
    
    private let cache = NSCache<NSURL, LocalImage>()
    
    /// Target Realm to update
    var configuration: Realm.Configuration = .defaultConfiguration
    
    private var realm: Realm {
        let realm = try! Realm(configuration: configuration)
        realm.autorefresh = false
        realm.refresh()
        
        return realm
    }
    
    public init(configuration: Realm.Configuration = .defaultConfiguration, loadURLs: Bool = false) {
        self.configuration = configuration
        if loadURLs {
            let assets = realm.objects(L.self)
            
            for asset in assets {
                update(for: asset)
            }
        }
    }
    
    public subscript(id: String) -> URL? {
        if let url = assetURLs[id] {
            return url
        }
                
        if let localAssetUrl = realm.object(ofType: L.self, forPrimaryKey: id)?.fileURL {
            assetURLs[id] = localAssetUrl
            
            return localAssetUrl
        }
        
        return nil
    }
    
    public func assetImage(url: URL) -> LocalImage? {
        if let image = cache.object(forKey: url as NSURL) {
            return image
        }
        
        if let data = try? Data(contentsOf: url), let image = LocalImage(data: data) {
            cache.setObject(image, forKey: url as NSURL)
            
            return image
        }
        
        return nil
    }
    
    public func update(for localAsset: L) {
        if let localUrl = localAsset.fileURL {
            assetURLs[localAsset.id] = localUrl
        }
    }
}
