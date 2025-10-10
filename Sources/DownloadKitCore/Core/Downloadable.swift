//
//  Downloadable.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 6/10/20.
//

import Foundation

public struct DownloadParameter: Codable, Sendable, Hashable, Equatable, RawRepresentable {
    public let rawValue: String
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public typealias DownloadParameters = [DownloadParameter: any Sendable]


public protocol Downloadable: Actor {
    /// Identifier of the download, usually an id
    var identifier: String { get }
    
    /// Total bytes reported by download agent
    var totalBytes: Int64 { get }
    
    /// Total bytes, if known ahead of time.
    var totalSize: Int64 { get }
    
    /// Bytes already transferred.
    var transferredBytes: Int64 { get }
    
    /// Download start date, empty if in queue.
    var startDate: Date? { get }
    
    /// Download finished date, empty until completed
    var finishedDate: Date? { get }
    
    /// Progress of the download
    var progress: Foundation.Progress? { get }
    
    /// Start download with parameters
    func start(with parameters: DownloadParameters)
    
    /// Cancel download in progress
    func cancel()
    
    /// Temporarily pause current download (if in progress)
    func pause()
}

public extension Downloadable {
    var totalBytes: Int64 { return 0 }
    var totalSize: Int64 { return 0 }
    
    func isEqual(to downloadable: Downloadable) async -> Bool {
        return await identifier == downloadable.identifier
    }
}

public extension Downloadable {
    static var highestPriority: Int { return Int.max }
}

public struct DownloadItemData : Codable, Sendable {
    static let decoder = JSONDecoder()
    static let encoder = JSONEncoder()
    
    // MARK: - Downloadable Properties
    public var url: URL
    
    /// JSON Serialized Metadata
    public var serializedMetadata: String?
    
    /// Task identifier, usually resource identifier. Must not be nil.
    public var identifier: String
    
    /// Total bytes reported by download agent
    public var totalBytes: Int64 = 0
    
    /// Total bytes, if known ahead of time.
    public var totalSize: Int64 = 0
    
    /// Bytes already transferred.
    public var transferredBytes: Int64 = 0
    
    /// Download start date
    public var startDate: Date?
    
    /// Download finished date
    public var finishedDate: Date?
    
    // MARK: - Codable
    
    private enum CodingKeys: String, CodingKey {
        case identifier
        case url
        case totalBytes
        case totalSize
        case startDate
        case finishedDate
    }
}

//func ==<L: Downloadable, R: Downloadable>(l: L, r: R) -> Bool {
//    return l.identifier == r.identifier
//}
