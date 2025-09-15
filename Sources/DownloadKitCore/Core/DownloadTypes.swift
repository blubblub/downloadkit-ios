//
//  DownloadTypes.swift
//  DownloadKit
//
//  Created by Dal Rupnik on 30.06.2025.
//

#if os(OSX)
import AppKit
public typealias LocalImage = NSImage
extension NSImage: @retroactive @unchecked Sendable {}
#elseif canImport(UIKit)
import UIKit
public typealias LocalImage = UIImage
#else
public typealias LocalImage = Never
#endif

import Foundation

public enum DownloadPriority: UInt, Sendable {
    case normal
    case high       // Will place download in priority queue.
    case urgent     // Will place download in priority queue and downgrade all other downloads.
}

public enum StoragePriority: String, Sendable {
    /// Cache Manager should permanently store the file. This should be used for offline mode.
    case permanent
    
    /// Cache Manager should place the file in temporary folder. Once system clears the folder
    /// due to space constraints, it will have to be redownloaded.
    case cached
}

public struct RequestOptions: Sendable {
    public var storagePriority: StoragePriority = .cached
    
    public init(storagePriority: StoragePriority = .cached) {
        self.storagePriority = storagePriority
    }
}

/// Completion block, having success flag and item identifier
public typealias ProgressCompletion = @Sendable (Bool, String) -> Void

/// Protocol for cache implementations that don't require specific database dependencies
public protocol ResourceFileRetrievable : Sendable {
    func fileURL(for id: String) -> URL?
}

public protocol ResourceDataRetrievable: Sendable {
    func data(for id: String) -> Data?
}

public protocol ResourceImageRetrievable : Sendable {
    func image(for id: String) -> LocalImage?
}

public protocol ResourceRetrievable : ResourceFileRetrievable, ResourceDataRetrievable, ResourceImageRetrievable {
    
}

public extension DownloadRequest {
    var resourceId : String {
        return resource.id
    }
}
