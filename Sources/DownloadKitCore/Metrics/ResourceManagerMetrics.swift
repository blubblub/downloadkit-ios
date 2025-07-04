//
//  ResourceManagerMetrics.swift
//  DownloadKit
//
//  Created by Dal Rupnik on 10/25/22.
//  Copyright © 2022 Blub Blub. All rights reserved.
//

import Foundation

/// Measured metrics on ResourceManager
public struct ResourceManagerMetrics: Sendable {
    
    public init() {}

    // MARK: - Private Properties
    private var updateDate = Date()
    private var transferredSinceLastDate = 0
    
    private var startBytesMap: [String: Int64] = [:]
    private var currentBytesMap: [String: Int64] = [:]
    
    // MARK: - Public Properties
    public var requested = 0
    public var downloadBegan = 0
    public var downloadCompleted = 0
    public var priorityIncreased = 0
    public var priorityDecreased = 0
    public var failed = 0
    public var retried = 0
    
    public var bytesTransferred: Int64 = 0
    public private(set) var downloadSpeedBytes: Int64 = 0
    
    /// Updates Download Speed calculation and bytes transferred tracking
    /// - Parameters:
    ///   - downloadable: downloadable to update metrics for
    ///   - isCompleted: whether the download is completed (for final byte tracking)
    public mutating func updateDownloadSpeed(downloadable: Downloadable? = nil, isCompleted: Bool = false) async {
        guard let identifier = await downloadable?.identifier else {
            return
        }
        
        if let downloadable = downloadable {
            let currentTransferredBytes = await downloadable.transferredBytes
            
            if self.startBytesMap[identifier] == nil {
                self.startBytesMap[identifier] = currentTransferredBytes
            }
            
            self.currentBytesMap[identifier] = currentTransferredBytes
            
            // Update total bytes transferred when download completes
            if isCompleted && currentTransferredBytes > 0 {
                // Add the completed download's bytes to total transferred
                if let startBytes = self.startBytesMap[identifier] {
                    let transferredInThisDownload = currentTransferredBytes - startBytes
                    self.bytesTransferred += max(0, transferredInThisDownload)
                } else {
                    // If we don't have start bytes, count all transferred bytes
                    self.bytesTransferred += currentTransferredBytes
                }
            }
        }
        
        if let downloadSpeed = self.calculateDownloadSpeed(lastUpdateDate: self.updateDate) {
            self.downloadSpeedBytes = downloadSpeed
            self.updateDate = Date()
            
            // Only clear the maps if calculating download speed
            // Keep them for completed download tracking
            if !isCompleted {
                self.startBytesMap.removeAll()
                self.currentBytesMap.removeAll()
            }
        }
        
        // Clean up completed downloads from tracking maps
        if isCompleted {
            self.startBytesMap.removeValue(forKey: identifier)
            self.currentBytesMap.removeValue(forKey: identifier)
        }
    }
    
    private func calculateDownloadSpeed(lastUpdateDate: Date) -> Int64? {
        guard fabs(lastUpdateDate.timeIntervalSinceNow) > 1.0 else {
            return nil
        }
        
        var totalTransferred: Int64 = 0
        
        // Calculate deltas since last date.
        for identifier in startBytesMap.keys {
            let startedTransferred = startBytesMap[identifier] ?? 0
            let currentTransferred = currentBytesMap[identifier] ?? 0
            
            totalTransferred += currentTransferred - startedTransferred
        }
        
        return totalTransferred
    }
}

extension ResourceManagerMetrics : CustomStringConvertible {
    public var description: String {
        let formatter = ByteCountFormatter()
        
        return String(format: "Requested: %d Began: %d Completed: %d Priority Inc.: %d Priority Dec.: %d Failed: %d Retried: %d Transferred: %@", requested, downloadBegan, downloadCompleted, priorityIncreased, priorityDecreased, failed, retried, formatter.string(fromByteCount: bytesTransferred))
    }
}
