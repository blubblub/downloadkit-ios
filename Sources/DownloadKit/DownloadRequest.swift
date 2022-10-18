//
//  DownloadRequest.swift
//
//  Created by Dal Rupnik on 10/18/22.
//

import Foundation

/// Hold references to downloads, so they can be properly handled.
public struct DownloadRequest: Identifiable, Equatable {
    public static func == (lhs: DownloadRequest, rhs: DownloadRequest) -> Bool {
        return lhs.id == rhs.id
    }
        
    public var id: String {
        return asset.id
    }
    
    public let asset: AssetFile
    public let options: RequestOptions
    public let mirror: AssetMirrorSelection
    
    public var downloadableIdentifier : String {
        return mirror.downloadable.identifier
    }
}

/// Returns download selection to retry.
public struct RetryDownloadRequest: Identifiable, Equatable {
    public var id : String {
        return retryRequest.id
    }
    
    public var downloadable : Downloadable {
        
        var nextDownloadable = retryRequest.mirror.downloadable
        
        // Increase priority after download fails, so the next attempt is prioritized higher and
        // not placed at the end of the download queue. We likely want this retry immediately.
        nextDownloadable.priority += 10000
        
        return nextDownloadable
    }
    
    public let retryRequest: DownloadRequest
    public let originalRequest: DownloadRequest
}
