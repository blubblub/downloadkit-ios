//
//  URLDownloadItem.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 26/09/2017.
//  Copyright © 2017 Blub Blub. All rights reserved.
//

import Foundation
import os.log

public extension DownloadParameter {
    static let urlDownloadTask = DownloadParameter(rawValue: "urlDownloadTask")
}

public actor WebDownloadItem : Downloadable {
        private var log: Logger = logDK
    /// Progress for older versions, before 11.0, stored internally and exposed via progress property.
    private var itemProgress: Foundation.Progress?
    
    public var url: URL {
        return data.url
    }
    
    // MARK: - Downloadable
    
    /// Identifier of the download, usually an id
    public var identifier: String { return data.identifier }
    
    /// Task priority in download queue (if needed), higher number means higher priority.
    public var priority: Int {
        get {
            return data.priority }
        set {
            data.priority = newValue
        }
    }
    
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
    
    // MARK: - Public Properties
    public private(set) var data: DownloadItemData
    public private(set) var task: URLSessionDownloadTask?
    
    public var progress: Foundation.Progress? {
        if let itemProgress = itemProgress {
            return itemProgress
        }
        
        // One is added, so the file move operation is counted in the progress.
        if totalSize > 0 {
            itemProgress = Foundation.Progress(totalUnitCount: totalSize + 1)
        }
        else if totalBytes > 0 {
            itemProgress = Foundation.Progress(totalUnitCount: totalBytes + 1)
        }
        
        return itemProgress
    }
        
    public init(identifier: String, url: URL, priority: Int = 0) {
        self.data = .init(url: url, identifier: identifier)
        self.data.priority = priority
    }
    
    public init?(task: URLSessionDownloadTask) {
        
        // Try to decode an item out of this, yes, we do create another instance here, but this way we ensure session
        // is initialized as it should be, without any crashes happening later on.
        guard let data = task.taskDescription?.data(using: .utf8),
              let item = try? DownloadItemData.decoder.decode(DownloadItemData.self, from: data) else {
            return nil
        }
        
        self.data = item
        self.task = task
    }
    
    public func start(with parameters: DownloadParameters) {
        data.startDate = Date()
        
        if let task = task {
            task.resume()
        } else {
            guard let task = parameters[.urlDownloadTask] as? URLSessionDownloadTask else {
                log.fault("Cannot start an WebDownloadItem without URLSessionDownloadTask: \(self.data.identifier)")
                return
            }
            
            self.task = task
            self.task?.resume()
        }
    }

    public func pause() {
        guard let task = task else {
            return
        }
        
        if task.state == .suspended {
            return
        }
        
        task.suspend()
    }

    public func cancel() {
        guard let task = task else {
            return
        }

        task.cancel()
    }
    
    // MARK: - Delegate Methods
    
    func didWriteData(bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if itemProgress == nil {
            itemProgress = Foundation.Progress(totalUnitCount: totalBytesExpectedToWrite + 1)
            data.totalBytes = totalBytesExpectedToWrite
        }
        
        data.transferredBytes = totalBytesWritten
        
        guard let itemProgress = itemProgress else {
            return
        }
        
        itemProgress.completedUnitCount = totalBytesWritten > itemProgress.totalUnitCount ? itemProgress.totalUnitCount - 1 : totalBytesWritten
    }
}

// MARK: - Hashable
//
//extension WebDownloadItem: @MainActor Hashable {
//    
//    public static func == (l: WebDownloadItem, r: WebDownloadItem) async -> Bool {
//        return await l.isEqual(to: r)
//    }
//    
//    public func hash(into hasher: inout Hasher) {
//        hasher.combine(identifier)
//    }
//}
