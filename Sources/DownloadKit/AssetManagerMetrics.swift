//
//  AssetManagerMetrics.swift
//  DownloadKit
//
//  Created by Dal Rupnik on 10/25/22.
//  Copyright © 2022 Blub Blub. All rights reserved.
//

import Foundation

/// Measured metrics on AssetManager
public class AssetManagerMetrics {
    // MARK: - Private Properties
    private var updateDate = Date()
    private var transferredSinceLastDate = 0
    
    private var startBytesMap = AtomicDictionary<String, Int64>()
    private var currentBytesMap = AtomicDictionary<String, Int64>()
    
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
    public func updateDownloadSpeed(item: Downloadable? = nil) {
        
        if let item = item {
            if startBytesMap[item.identifier] == nil {
                startBytesMap[item.identifier] = item.transferredBytes
            }
            
            currentBytesMap[item.identifier] = item.transferredBytes
        }
        
        if let downloadSpeed = calculateDownloadSpeed(lastUpdateDate: updateDate) {
            downloadSpeedBytes = downloadSpeed
            updateDate = Date()
            
            startBytesMap.removeAll()
            currentBytesMap.removeAll()
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

extension AssetManagerMetrics : CustomStringConvertible {
    public var description: String {
        let formatter = ByteCountFormatter()
        
        return String(format: "Requested: %d Began: %d Completed: %d Priority Inc.: %d Priority Dec.: %d Failed: %d Retried: %d Transferred: %@", requested, downloadBegan, downloadCompleted, priorityIncreased, priorityDecreased, failed, retried, formatter.string(fromByteCount: bytesTransferred))
    }
}
