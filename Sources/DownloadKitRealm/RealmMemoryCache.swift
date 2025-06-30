//
//  AssetCache.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 23/08/2017.
//  Copyright © 2017 Blub Blub. All rights reserved.
//

import Foundation
import DownloadKitCore
import RealmSwift

#if canImport(UIKit)
import UIKit
#endif

#if os(OSX)
import AppKit
public typealias LocalImage = NSImage
extension NSImage: @retroactive @unchecked Sendable {}
#else
public typealias LocalImage = UIImage
extension UIImage: @retroactive @unchecked Sendable {}
#endif

/// Will cache asset URL's and images in memory for quick access.
/// URL's are stored in a local dictionary, images are stored in NSCache.
/// Images are stored as `UIImage`
/// Note:
/// Cache Manager will load the image into memory after downloading it.
public actor RealmMemoryCache<L: Object>: ResourceFileCacheable where L: LocalResourceFile {
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
        if let url = assetURLs[id] {
            return url
        }
        
        guard let realm = try? self.realm else {
            return nil
        }
        
        autoreleasepool {
            if let localAssetUrl = realm.object(ofType: L.self, forPrimaryKey: id)?.fileURL {
                assetURLs[id] = localAssetUrl
            }
        }
        
        return assetURLs[id]
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
    
    // MARK: - ResourceFileCacheable
    
    public func currentAssets() async -> [ResourceFile] {
        // This should return cached assets from Realm, for now returning empty
        return []
    }
    
    public func currentDownloadRequests() async -> [DownloadRequest] {
        // Memory cache doesn't store download requests
        return []
    }
}
