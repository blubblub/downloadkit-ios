//
//  Downloadable.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 6/10/20.
//

import Foundation

public struct DownloadParameter: Codable, Hashable, Equatable, RawRepresentable {
    public let rawValue: String
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public typealias DownloadParameters = [DownloadParameter: Any]


public protocol Downloadable: CustomStringConvertible {
    /// Identifier of the download, usually an id
    var identifier: String { get }
    
    /// Task priority in download queue (if needed), higher number means higher priority.
    var priority: Int { get set }
    
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
    var priority: Int { return 0 }
    var totalBytes: Int64 { return 0 }
    var totalSize: Int64 { return 0 }
    
    func isEqual(to downloadable: Downloadable) -> Bool {
        return identifier == downloadable.identifier
    }
}

public extension Downloadable {
    static var highestPriority: Int { return Int.max }
}

func ==<L: Downloadable, R: Downloadable>(l: L, r: R) -> Bool {
    return l.identifier == r.identifier
}
