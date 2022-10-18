//
//  AssetFileManager.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 11/2/20.
//

import Foundation
import os.log

public protocol AssetCacheable: AssetFileCacheable {
    
    /// Mirror policy.
    var mirrorPolicy: MirrorPolicy { get set }
    
    /// Returns downloadable items, that are not stored locally.
    /// - Parameters:
    ///   - assets: assets we're interested in.
    ///   - options: request options.
    func requestDownloads(assets: [AssetFile], options: RequestOptions) -> [DownloadRequest]
        
    /// Returns download selection for specific downloadable ID that has failed or completed.
    /// - Parameter downloadable: downloadable
    /// - Returns: DownloadRequest
    func downloadRequest(for downloadable: Downloadable) -> DownloadRequest?
    
    /// Called after the download finishes successfully.
    /// - Parameters:
    ///   - downloadable: item that finished downloading.
    ///   - location: where the item was stored.
    func download(_ downloadable: Downloadable, didFinishTo location: URL) -> DownloadRequest?
    
    /// Called if download fails. Return new `Downloadable` item to retry download
    /// - Parameters:
    ///   - downloadable: item that failed
    ///   - error: error describing why the download failed.
    /// - Returns:
    ///   - RetryDownloadRequest: If cache has no info about this request, it will return in.
    ///                           Otherwise object will be present with it's original download req.
    func download(_ downloadable: Downloadable, didFailWith error: Error) -> RetryDownloadRequest?
    
    /// Cleans up cache.
    /// - Parameter urls: urls to ignore while clean up process.
    func cleanup(excluding urls: Set<URL>)
}
