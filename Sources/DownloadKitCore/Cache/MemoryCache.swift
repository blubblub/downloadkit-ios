//
//  RealmMemoryCache.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 23/08/2017.
//  Copyright © 2017 Blub Blub. All rights reserved.
//

import Foundation

public final class MemoryCache : @unchecked Sendable, ResourceFileRetrievable, ResourceImageRetrievable {
    private let urlCache = NSCache<NSString, NSURL>()
    
    private let imageCache = NSCache<NSString, LocalImage>()
    
    public init() {
        
    }
        
    public func fileURL(for id: String) -> URL? {
        if let url = urlCache.object(forKey: id as NSString) {
            return url as URL
        }
        
        return nil
    }
    
    public func image(for id: String) -> LocalImage? {
        if let image = imageCache.object(forKey: id as NSString) {
            return image
        }
                
        return nil
    }
    
    public func update(image: LocalImage, for id: String) {
        imageCache.setObject(image, forKey: id as NSString)
    }
    
    public func update(fileURL: URL, for id: String) {
        urlCache.setObject(fileURL as NSURL, forKey: id as NSString)
    }
}
