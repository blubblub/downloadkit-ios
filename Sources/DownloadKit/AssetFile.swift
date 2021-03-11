//
//  AssetFile.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 11/2/20.
//

import Foundation

public typealias AssetFileInfo = [String: Any]

/// Base DownloadKit Asset that can be downloaded.
public protocol AssetFile {
    var id: String { get }
    var main: AssetFileMirror { get }
    var alternatives: [AssetFileMirror] { get }
    var fileURL: URL? { get }
    
    var modifyDate: Date? { get }
}

public extension AssetFile {
    var modifyDate: Date? {
        return nil
    }
}

public protocol AssetFileMirror {
    /// File Mirror has a specific identifier as well.
    var id: String { get }
    
    /// Location of the mirror
    var location: String { get }
    
    /// Certain Metadata of the mirror
    var info: AssetFileInfo { get }
    
    /// Returns downloadable object for
    var downloadable: Downloadable? { get }
}

public protocol LocalAssetFile {
    var id: String { get set }
    
    var fileURL: URL? { get set }
    
    var modifyDate: Date? { get set }
    
    /// Storage priority when the file was saved locally.
    var storage: StoragePriority { get set }
    
    static func targetUrl(for asset: AssetFile, mirror: AssetFileMirror, at url: URL, storagePriority: StoragePriority, file: FileManager) -> URL
}

public extension LocalAssetFile {
    var modifyDate: Date? {
        get { return nil }
        set { }
    }
}

public extension AssetFileMirror {
    var downloadable: Downloadable? {
        return createDownloadable()
    }
    
    func createDownloadable() -> Downloadable? {
        guard let url = URL(string: location) else {
            return nil
        }
        
        if location.starts(with: "http") {
            return WebDownloadItem(identifier: id, url: url)
        }
        
        if location.starts(with: "cloudkit://") {
            return CloudKitDownloadItem(identifier: id, url: url)
        }
        
        return nil
    }
}
