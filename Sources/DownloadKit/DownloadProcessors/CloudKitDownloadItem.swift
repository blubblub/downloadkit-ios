//
//  CloudKitDownloadItem.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 10/19/20.
//

import Foundation

public class CloudKitDownloadItem: Codable, Downloadable, CustomStringConvertible {
    
    /// CloudKit URL to download from
    public var url: URL
    
    // MARK: - Downloadable Properties

    /// Task identifier, usually asset identifier. Must not be nil.
    public var identifier: String
    
    /// Task priority in download queue (if needed), higher number means higher priority.
    public var priority: Int
    
    /// Total bytes reported by download agent
    public var totalBytes: Int64 = 0
    
    /// Total bytes, if known ahead of time.
    public var totalSize: Int64 = 0
    
    /// Download start date
    public var startDate: Date?
    
    /// Download finished date
    public var finishedDate: Date?
    
    public var assetFile: AssetMirrorSelection?
    
    var didSendStartTransferNotification = false
    
    // MARK: - Codable
    
    private enum CodingKeys: String, CodingKey {
        case identifier
        case url
        case priority
        //case recordData
        //case targetUrl
        case totalBytes
        case totalSize
        case startDate
        case finishedDate
    }
    
    public init(identifier: String, url: URL, priority: Int = 0) {
        self.identifier = identifier
        self.url = url
        self.priority = priority
    }
    
    private var itemProgress: Foundation.Progress?
    
    public var progress: Foundation.Progress? {
        if let itemProgress = itemProgress {
            return itemProgress
        }
        
        // One is added, so the file move operation is counted in the progress.

        if totalSize > 0 {
            itemProgress = Foundation.Progress(totalUnitCount: totalSize + 1)
        }
        
        return itemProgress
    }
    
    public func start(with parameters: DownloadParameters) {
        startDate = Date()
    }
    
    public func pause() {
        
    }
    
    public func cancel() {
        
    }
    
    public var description: String {
        return "[CloudKitItem]: \(identifier)"
    }
    
    public static func == (lhs: CloudKitDownloadItem, rhs: CloudKitDownloadItem) -> Bool {
        return lhs.identifier == rhs.identifier
    }
    
    func update(progress: Double) {
        if itemProgress == nil && totalSize > 0 {
            itemProgress = Foundation.Progress(totalUnitCount: totalSize)
        }
        
        guard let itemProgress = itemProgress else {
            return
        }
        
        let completedUnitCount = Int64(Double(itemProgress.totalUnitCount) * progress)
        
        itemProgress.completedUnitCount = completedUnitCount > itemProgress.totalUnitCount ? itemProgress.totalUnitCount : completedUnitCount
    }
    
    func finish() {
        finishedDate = Date()
    }
}

// MARK: - CloudKit Convenience Methods
import CloudKit

public extension CloudKitDownloadItem {
    var recordID: CKRecord.ID? {
        // Parse from URL: cloudkit://<container>:<zone_id>:<zone_owner>:<record_type>:<record_id>
        // Parse from URL: cloudkit://<container>:<record_type>:<record_id>
        
        let urlComponents = url.absoluteString.replacingOccurrences(of: "cloudkit://", with: "").split(separator: "/").map { String($0) }
        
        if urlComponents.count == 3 {
            return CKRecord.ID(recordName: urlComponents.last!)
        }
        else if urlComponents.count == 5 {
            return CKRecord.ID(recordName: urlComponents.last!, zoneID: CKRecordZone.ID(zoneName: urlComponents[1], ownerName: urlComponents[2]))
        }
        
        return nil
    }
}
