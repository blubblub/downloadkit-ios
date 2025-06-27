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
    static let urlSession = DownloadParameter(rawValue: "urlSession")
}

// Actor can inherit NSObject, as a special exception.
public actor WebDownload : NSObject, Downloadable {
    private var log: Logger = logDK
    
    /// Progress for older versions, before 11.0, stored internally and exposed via progress property.
    private var downloadProgress: Foundation.Progress?
    
    private var data: DownloadItemData
    
    private var progressUpdates: [(@Sendable (Int64, Int64) -> Void)] = []
    private var completions: [(@Sendable (Result<URL, Error>) -> Void)] = []
    
    public var url: URL {
        return data.url
    }
    
    // MARK: - Downloadable
    
    /// Identifier of the download, usually an id
    public var identifier: String { return data.identifier }
    
    /// Task priority in download queue (if needed), higher number means higher priority.
    public var priority: Int {
        return data.priority
    }
    
    public func set(priority: Int) {
        data.priority = priority
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
    public private(set) var task: URLSessionDownloadTask?
    
    public var progress: Foundation.Progress? {
        if let downloadProgress = downloadProgress {
            return downloadProgress
        }
        
        // One is added, so the file move operation is counted in the progress.
        if totalSize > 0 {
            downloadProgress = Foundation.Progress(totalUnitCount: totalSize + 1)
        }
        else if totalBytes > 0 {
            downloadProgress = Foundation.Progress(totalUnitCount: totalBytes + 1)
        }
        
        return downloadProgress
    }
    
    // MARK: - Constructors
        
    public init(identifier: String, url: URL, priority: Int = 0, completion: (@Sendable (Result<URL, Error>) -> Void)? = nil, progressUpdate: (@Sendable (Int64, Int64) -> Void)? = nil) {
        self.data = .init(url: url, identifier: identifier)
        self.data.priority = priority
        
        if let progressUpdate {
            self.progressUpdates.append(progressUpdate)
        }
        
        if let completion {
            self.completions.append(completion)
        }
    }
    
    public init?(task: URLSessionDownloadTask, completion: (@Sendable (Result<URL, Error>) -> Void)? = nil, progressUpdate: (@Sendable (Int64, Int64) -> Void)? = nil) {
        
        // Try to decode an item out of this, yes, we do create another instance here, but this way we ensure session
        // is initialized as it should be, without any crashes happening later on.
        guard let data = task.taskDescription?.data(using: .utf8),
              let item = try? DownloadItemData.decoder.decode(DownloadItemData.self, from: data) else {
            return nil
        }
        
        self.data = item
        self.task = task
        
        if let progressUpdate {
            self.progressUpdates.append(progressUpdate)
        }
        
        if let completion {
            self.completions.append(completion)
        }
    }
    
    // MARK: - Public Methods
    
    public func start(with parameters: DownloadParameters) {
        data.startDate = Date()
        
        var downloadTask = task
        
        if downloadTask == nil {
            guard let session = parameters[.urlSession] as? URLSession else {
                log.fault("Cannot start an WebDownloadItem without URLSessionDownloadTask: \(self.data.identifier)")
                return
            }
            
            downloadTask = createTask(with: session)
            self.task = downloadTask
        }
        
        downloadTask?.delegate = self
        downloadTask?.resume()
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
    
    public func addCompletion(_ completion: @escaping (@Sendable (Result<URL, Error>) -> Void)) {
        self.completions.append(completion)
    }
    
    public func addProgressUpdate(_ progressUpdate: @escaping (@Sendable (Int64, Int64) -> Void)) {
        self.progressUpdates.append(progressUpdate)
    }
    
    // MARK: - Private Methods
    
    private func didWriteData(bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if downloadProgress == nil {
            downloadProgress = Foundation.Progress(totalUnitCount: totalBytesExpectedToWrite + 1)
            data.totalBytes = totalBytesExpectedToWrite
        }
        
        data.transferredBytes = totalBytesWritten
        
        guard let downloadProgress = downloadProgress else {
            return
        }
        
        downloadProgress.completedUnitCount = totalBytesWritten > downloadProgress.totalUnitCount ? downloadProgress.totalUnitCount - 1 : totalBytesWritten
    }
    
    private func createTask(with session: URLSession) -> URLSessionDownloadTask {
        
        let task = session.downloadTask(with: URLRequest(url: url))
        
        if priority > 0 {
            task.priority = URLSessionDownloadTask.highPriority
        }
        
        if totalSize > 0 {
            task.countOfBytesClientExpectsToReceive = totalSize
        }
        
        task.taskDescription = String(data: try! DownloadItemData.encoder.encode(data), encoding: .utf8)
        return task
    }
}

extension WebDownload : URLSessionDownloadDelegate {
    nonisolated public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        Task {
            // TODO: Check this. Previously, we needed to finish the MOVE operation on the same thread before
            // exiting this method. Will see if this is still the case, if yes, ASYNC here will not work.
            for completion in await self.completions {
                completion(.success(location))
            }
        }
    }
        
    nonisolated public func urlSession(_ session: Foundation.URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task {
            // Forward the call to correct item, to correctly update progress.
            await didWriteData(bytesWritten: bytesWritten, totalBytesWritten: totalBytesWritten, totalBytesExpectedToWrite: totalBytesExpectedToWrite)
            
            let progressUpdates = await self.progressUpdates
            
            for progressUpdate in progressUpdates {
                // TODO: why we need
                await progressUpdate(totalBytesWritten, progress?.completedUnitCount ?? 0)
            }
        }
    }
    
    nonisolated public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        Task {
            let error = error ?? URLError(.unknown)
            
            for completion in await self.completions {
                completion(.failure(error))
            }
        }
    }
    
    nonisolated public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task {
            let error = error ?? URLError(.unknown)
            
            for completion in await self.completions {
                completion(.failure(error))
            }
        }
    }
}

// MARK: - Hashable
// TODO: Implement this and switch implementation back to set, when Swift 6.2 is available.
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
