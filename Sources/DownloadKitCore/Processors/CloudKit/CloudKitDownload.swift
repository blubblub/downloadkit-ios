//
//  CloudKitDownload.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 10/19/20.
//

import Foundation

public actor CloudKitDownload: Downloadable {
    
    private var data: DownloadItemData
        
    // MARK: - Downloadable
    /// Identifier of the download, usually an id
    public var identifier: String { return data.identifier }
    
    /// Total bytes reported by download agent
    public var totalBytes: Int64 { return data.totalBytes }
    
    /// Total bytes, if known ahead of time.
    public var totalSize: Int64 { return data.totalSize }
    
    /// Bytes already transferred.
    public var transferredBytes: Int64 { return data.transferredBytes }
    
    /// Download start date, empty if in queue.
    public var startDate: Date? { return data.startDate }
    
    /// Download finished date, empty until completed
    public var finishedDate: Date? { return data.finishedDate }
        
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
        self.data = .init(url: url, identifier: identifier)
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
        data.startDate = Date()
    }
    
    public func pause() {
        
    }
    
    public func cancel() {
        
    }
    
    public var description: String {
        return "[CloudKitItem]: \(identifier)"
    }
//    
//    public static func == (lhs: CloudKitDownloadItem, rhs: CloudKitDownloadItem) -> Bool {
//        return lhs.identifier == rhs.identifier
//    }
    
    public func update(totalBytes: Int64) {
        data.totalBytes = totalBytes
    }
    
    public func update(progress: Double) {
        if itemProgress == nil && totalSize > 0 {
            itemProgress = Foundation.Progress(totalUnitCount: totalSize)
        }
        
        guard let itemProgress = itemProgress else {
            return
        }
        
        // Update transferred bytes.
        data.transferredBytes = Int64(Double(totalSize) * progress)
        
        if progress >= 1.0 {
            data.transferredBytes = totalSize
        }
        
        let completedUnitCount = Int64(Double(itemProgress.totalUnitCount) * progress)
        
        itemProgress.completedUnitCount = completedUnitCount > itemProgress.totalUnitCount ? itemProgress.totalUnitCount : completedUnitCount
    }
    
    public func finish() {
        data.finishedDate = Date()
    }
}

// MARK: - CloudKit Convenience Methods
import CloudKit

public extension CloudKitDownload {
    var recordID: CKRecord.ID? {
        // Parse from URL: cloudkit://<container>:<zone_id>:<zone_owner>:<record_type>:<record_id>
        // Parse from URL: cloudkit://<container>:<record_type>:<record_id>
        
        let urlComponents = data.url.absoluteString.replacingOccurrences(of: "cloudkit://", with: "").split(separator: "/").map { String($0) }
        
        if urlComponents.count == 3 {
            return CKRecord.ID(recordName: urlComponents.last!)
        }
        else if urlComponents.count == 5 {
            return CKRecord.ID(recordName: urlComponents.last!, zoneID: CKRecordZone.ID(zoneName: urlComponents[1], ownerName: urlComponents[2]))
        }
        
        return nil
    }
}
