//
//  ResourceCachable.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 11/2/20.
//

import Foundation
import os.log

public protocol ResourceCachable: Actor, ResourceRetrievable {

    /// Returns true, if actual file is available in the cache.
    func isAvailable(resource: ResourceFile) -> Bool
    
    /// Mirror policy.
    var mirrorPolicy: MirrorPolicy { get set }
    
    /// Returns downloadable items, that are not stored locally.
    /// - Parameters:
    ///   - resources: resources we're interested in.
    ///   - options: request options.
    func requestDownloads(resources: [ResourceFile], options: RequestOptions) async -> [DownloadRequest]
    
    /// Returns download request for certain downloadable, if cache created it.
    /// - Parameter downloadable: item that we need request for.
    /// - Returns: original request object.
    func downloadRequest(for downloadable: Downloadable) async -> DownloadRequest?
    
    /// Called after the download finishes successfully.
    /// - Parameters:
    ///   - downloadable: item that finished downloading.
    ///   - location: where the item was stored.
    func download(_ downloadable: Downloadable, didFinishTo location: URL) async throws -> DownloadRequest?
    
    /// Called if download fails. Return new `Downloadable` item to retry download
    /// - Parameters:
    ///   - downloadable: item that failed
    ///   - error: error describing why the download failed.
    /// - Returns:
    ///   - RetryDownloadRequest: If cache has no info about this request, it will return nil.
    ///                           Otherwise object will be present with it's original download req.
    func download(_ downloadable: Downloadable, didFailWith error: Error) async -> RetryDownloadRequest?
    
    /// Cleans up cache.
    /// - Parameter urls: urls to ignore while clean up process.
    func cleanup(excluding ids: Set<String>)
}

public extension ResourceFile {
    func isAvailable(in cache: ResourceCachable) async -> Bool {
        return await cache.isAvailable(resource: self)
    }
}


