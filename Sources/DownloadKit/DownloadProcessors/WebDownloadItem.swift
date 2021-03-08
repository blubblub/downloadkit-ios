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

open class WebDownloadItem: Codable, Downloadable, CustomStringConvertible {
    
    // MARK: - Public Properties
    
    public var log: OSLog = logDK
    
    /// Url to download.
    public var url: URL
    
    /// URLSessionDownloadTask created for this download item
    public private(set) var task: URLSessionDownloadTask?
    
    // MARK: - Downloadable Properties
    
    /// Task identifier, usually asset identifier. Must not be nil.
    public var identifier: String
    
    /// Task priority in download queue (if needed), higher number means higher priority.
    public var priority: Int = 0
    
    /// Total bytes reported by download agent
    public var totalBytes: Int64 = 0
    
    /// Total bytes, if known ahead of time.
    public var totalSize: Int64 = 0
    
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
    
    /// Progress for older versions, before 11.0, stored internally and exposed via progress property.
    private var itemProgress: Foundation.Progress?
    
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
    
    // MARK: - CustomStringConvertible
    
    public var description: String {
        return "[URLDownloadItem]: \(identifier) url: \(url.absoluteString)"
    }
    
    public init(identifier: String, url: URL, priority: Int = 0) {
        self.identifier = identifier
        self.url = url
        self.priority = priority
    }
    
    public init?(task: URLSessionDownloadTask) {
        
        // Try to decode an item out of this, yes, we do create another instance here, but this way we ensure session
        // is initialized as it should be, without any crashes happening later on.
        guard let data = task.taskDescription?.data(using: .utf8),
              let item = try? WebDownloadItem.decoder.decode(WebDownloadItem.self, from: data) else {
            return nil
        }
        
        self.task = task
        self.identifier = item.identifier
        self.url = item.url
        self.totalBytes = item.totalBytes
        self.totalSize = item.totalSize
        self.startDate = item.startDate
    }
    
    public func start(with parameters: DownloadParameters) {
        if let task = task {
            task.resume()
        } else {
            guard let task = parameters[.urlDownloadTask] as? URLSessionDownloadTask else {
                log.fault("Cannot start an WebDownloadItem without URLSessionDownloadTask: %@", identifier)
                return
            }
            
            startDate = Date()
            
            self.task = task
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
        }
        
        guard let itemProgress = itemProgress else {
            return
        }
        
        itemProgress.completedUnitCount = totalBytesWritten > itemProgress.totalUnitCount ? itemProgress.totalUnitCount - 1 : totalBytesWritten
    }
}
