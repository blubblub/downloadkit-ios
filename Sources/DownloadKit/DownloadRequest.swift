//
//  DownloadRequest.swift
//
//  Created by Dal Rupnik on 10/18/22.
//

import Foundation

/// Hold references to downloads, so they can be properly handled.
public struct DownloadRequest: Identifiable, Equatable, Sendable {
    public static func == (lhs: DownloadRequest, rhs: DownloadRequest) -> Bool {
        return lhs.id == rhs.id
    }
        
    public var id: String {
        return resource.id
    }
    
    public let resource: ResourceFile
    public let options: RequestOptions
    public let mirror: ResourceMirrorSelection
    
    public func downloadableIdentifier() async -> String {
        return await mirror.downloadable.identifier
    }
    
//    public var downloadableIdentifier : String {
//        return mirror.downloadable.identifier
//    }
}

/// Returns download selection to retry.
public struct RetryDownloadRequest: Identifiable, Equatable {
    public var id : String {
        return originalRequest.id
    }
    
    public func downloadable() async -> Downloadable? {
        
        let nextDownloadable = retryRequest?.mirror.downloadable
        
        // Increase priority after download fails, so the next attempt is prioritized higher and
        // not placed at the end of the download queue. We likely want this retry immediately.
        if let currentPriority = await nextDownloadable?.priority {
            await nextDownloadable?.set(priority: currentPriority + 10000)
        }
        
        return nextDownloadable
    }
    
    public let retryRequest: DownloadRequest?
    public let originalRequest: DownloadRequest
}
