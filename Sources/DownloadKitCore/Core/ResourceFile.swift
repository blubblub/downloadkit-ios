//
//  ResourceFile.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 11/2/20.
//

import Foundation

public typealias ResourceFileInfo = [String: any Sendable]

/// Base DownloadKit Resource that can be downloaded.
public protocol ResourceFile : Sendable {
    var id: String { get }
    var main: ResourceFileMirror { get }
    var alternatives: [ResourceFileMirror] { get }
    var fileURL: URL? { get }
    
    var modifyDate: Date? { get }
}

public extension ResourceFile {
    var modifyDate: Date? {
        return nil
    }
}

public protocol ResourceFileMirror : Sendable {
    /// File Mirror has a specific identifier as well.
    var id: String { get }
    
    /// Location of the mirror
    var location: String { get }
    
    /// Certain Metadata of the mirror
    var info: ResourceFileInfo { get }
    
    /// Returns downloadable object for
    var downloadable: Downloadable? { get }
}

public protocol LocalResourceFile : Sendable {
    var id: String { get set }
    
    var fileURL: URL? { get set }
    
    var modifyDate: Date? { get set }
    
    /// Storage priority when the file was saved locally.
    var storage: StoragePriority { get set }
    
    static func targetUrl(for resource: ResourceFile, mirror: ResourceFileMirror, at url: URL, storagePriority: StoragePriority, file: FileManager) -> URL
}

public extension LocalResourceFile {
    var modifyDate: Date? {
        get { return nil }
        set { }
    }
}

public extension ResourceFileMirror {
    var downloadable: Downloadable? {
        return createDownloadable()
    }
    
    func createDownloadable() -> Downloadable? {
        guard let url = URL(string: location) else {
            return nil
        }
        
        if location.starts(with: "http") {
            return WebDownload(identifier: id, url: url)
        }
        
        if location.starts(with: "cloudkit://") {
            return CloudKitDownload(identifier: id, url: url)
        }
        
        return nil
    }
}
