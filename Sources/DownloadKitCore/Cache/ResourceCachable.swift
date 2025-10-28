//
//  ResourceCachable.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 11/2/20.
//

import Foundation
import os.log

public struct DownloadProcessingState : Sendable {
    public init(isFinished: Bool, isDownloading: Bool) {
        self.isFinished = isFinished
        self.isDownloading = isDownloading
    }
    
    let isFinished: Bool
    let isDownloading: Bool
    
    public var shouldDownload: Bool {
        return !(isFinished || isDownloading)
    }
}

public protocol ResourceCachable: Sendable, ResourceRetrievable {

    /// Returns true, if actual file is available in the cache.
    func isAvailable(resource: ResourceFile) -> Bool
    
    // MARK: - Methods without any side effects.
    
    /// Returns downloadable items, that are not stored locally.
    /// - Parameters:
    ///   - resources: resources we're interested in.
    ///   - options: request options.
    func requestDownloads(resources: [ResourceFile], options: RequestOptions) async -> [DownloadRequest]
    
    /// Returns download requests for certain downloadable, if cache is processing it.
    /// - Parameter downloadable: item that we need request for.
    /// - Returns: original request object.
    func downloads(for downloadTask: DownloadTask) async -> [DownloadTask]
    
    /// Update storage location for files in cache.
    /// - Parameter resources: items that we adjust storage for
    /// - Parameter storage: desired storage priority
    func updateStorage(resources: [ResourceFile], storage: StoragePriority)
    
    // MARK: - Methods that perform actions
    
    /// Download request will be processed.
    /// - Parameters:
    ///   - request: download request returned from requestDownloads method.
    /// - Returns: true, if download is not cached yet.
    func download(startProcessing request: DownloadTask) async -> DownloadProcessingState
    
    /// Called after the download finishes successfully.
    /// - Parameters:
    ///   - downloadable: item that finished downloading.
    ///   - location: where the item was stored.
    func download(_ downloadTask: DownloadTask, downloadable: Downloadable, didFinishTo location: URL) async throws
    
    /// Called if download fails. Return new `Downloadable` item to retry download
    /// - Parameters:
    ///   - downloadable: item that failed
    ///   - error: error describing why the download failed.
    /// - Returns:
    ///   - RetryDownloadRequest: If cache has no info about this request, it will return nil.
    ///                           Otherwise object will be present with it's original download req.
    func download(_ downloadTask: DownloadTask, didFailWith error: Error) async
    
    /// Cleans up cache.
    /// - Parameter urls: urls to ignore while clean up process.
    func cleanup(excluding ids: Set<String>)
}

public extension ResourceFile {
    func isAvailable(in cache: ResourceCachable) async -> Bool {
        return cache.isAvailable(resource: self)
    }
}


