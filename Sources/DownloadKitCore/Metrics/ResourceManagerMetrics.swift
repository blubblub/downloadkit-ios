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
    
    /// Updates Download Speed calculation
    /// - Parameters:
    ///   - item: downloadable
    ///   - isFinished: if item finished downloading
    public mutating func updateDownloadSpeed(downloadable: Downloadable? = nil) async {
        guard let identifier = await downloadable?.identifier else {
            return
        }
        
        if let downloadable = downloadable {
            if self.startBytesMap[identifier] == nil {
                self.startBytesMap[identifier] = await downloadable.transferredBytes
            }
            
            self.currentBytesMap[identifier] = await downloadable.transferredBytes
        }
        
        if let downloadSpeed = self.calculateDownloadSpeed(lastUpdateDate: self.updateDate) {
            self.downloadSpeedBytes = downloadSpeed
            self.updateDate = Date()
            
            self.startBytesMap.removeAll()
            self.currentBytesMap.removeAll()
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
