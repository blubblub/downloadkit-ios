//
//  AssetFileManager.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 11/2/20.
//

import Foundation
import os.log

public protocol AssetCacheable: AssetFileCacheable {
    var mirrorPolicy: MirrorPolicy { get set }
    
    /// Returns downloadable items, that are not stored locally.
    /// - Parameters:
    ///   - assets: assets we're interested in.
    ///   - options: request options.
    func requestDownloads(assets: [AssetFile], options: RequestOptions) -> [Downloadable]
        
    func download(downloadable: Downloadable, didFinishTo location: URL) -> LocalAssetFile?
    
    // If the download fails, if downloadable is returned we should retry.
    func download(downloadable: Downloadable, didFailWith error: Error) -> Downloadable?
    
    func cleanup(excluding urls: Set<URL>)
}
