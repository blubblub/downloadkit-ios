//
//  DownloadTypes.swift
//  DownloadKit
//
//  Created by Dal Rupnik on 30.06.2025.
//

import Foundation

public enum DownloadPriority: Sendable {
    case normal
    case high
}

public enum StoragePriority: String, Sendable {
    /// Cache Manager should permanently store the file. This should be used for offline mode.
    case permanent
    
    /// Cache Manager should place the file in temporary folder. Once system clears the folder
    /// due to space constraints, it will have to be redownloaded.
    case cached
}

public struct RequestOptions: Sendable {
    public var downloadPriority: DownloadPriority = .normal
    public var storagePriority: StoragePriority = .cached
    
    public init(downloadPriority: DownloadPriority = .normal,
                storagePriority: StoragePriority = .cached) {
        self.downloadPriority = downloadPriority
        self.storagePriority = storagePriority
    }
}

/// Completion block, having success flag and item identifier
public typealias ProgressCompletion = (Bool, String) -> Void

/// Protocol for cache implementations that don't require specific database dependencies
public protocol ResourceFileCacheable {
    func currentResources() async -> [ResourceFile]
    func currentDownloadRequests() async -> [DownloadRequest]
    subscript(id: String) -> URL? { get async }
}

// MARK: - Extensions

public extension Array {
    func unique(_ by: ((Element) -> String)) -> Array {
        var seen: [String: Bool] = [:]
        
        return self.filter { seen.updateValue(true, forKey: by($0)) == nil }
    }
}

public extension Array where Element: Sendable {
    func filterAsync(_ transform: @escaping @Sendable (Element) async -> Bool) async -> [Element] {
        var finalResult = Array<Element>()
        
        for element in self {
            if await transform(element) {
                finalResult.append(element)
            }
        }
        
        return finalResult
    }
    
    func asyncContains(_ predicate: @escaping @Sendable (Element) async -> Bool) async -> Bool {
        for element in self {
            if await predicate(element) {
                return true
            }
        }
        return false
    }
}

public extension DownloadRequest {
    func resourceIdentifier() async -> String {
        return resource.id
    }
}
