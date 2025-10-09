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
    private let log = Logger.logWebDownload
    
    /// Progress for older versions, before 11.0, stored internally and exposed via progress property.
    private var downloadProgress: Foundation.Progress?
    
    private var data: DownloadItemData
    
    private var progressUpdates: [(@Sendable (Int64, Int64) -> Void)] = []
    private var completions: [(@Sendable (Result<URL, Error>) -> Void)] = []
    
    public var url: URL {
        return data.url
    }
    
    private let isHighPriority: Bool
    
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
        
    public init(identifier: String, url: URL, isHighPriority: Bool = false, completion: (@Sendable (Result<URL, Error>) -> Void)? = nil, progressUpdate: (@Sendable (Int64, Int64) -> Void)? = nil) {
        self.data = .init(url: url, identifier: identifier)
        self.isHighPriority = isHighPriority
        
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
        
        self.isHighPriority = task.priority == URLSessionDownloadTask.highPriority
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
        
        // Delegate is handled at the session level by WebDownloadProcessor
        
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
        
        if isHighPriority {
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
        log.info("WebDownload delegate: didFinishDownloadingTo called at \(location)")
        
        // File is already moved, just call completions.
        if location.absoluteString.contains(FileManager.default.temporaryDirectory.absoluteString) {
            Task {
                await completeDownload(url: location, error: nil)
            }
        }
        else {
            do {
                // Move the file to a temporary location, otherwise it gets removed by the system immediately after this function completes
                let tempLocation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-download.tmp")
                try FileManager.default.moveItem(at: location, to: tempLocation)
                log.info("Successfully moved file to \(tempLocation)")
                
                Task {
                    await completeDownload(url: tempLocation, error:  nil)
                }
            } catch let error {
                Task {
                    let downloadKitError = DownloadKitError.from(error as NSError)
                    await completeDownload(url: nil, error: downloadKitError)
                }
            }
        }
    }
    
    public func completeDownload(url: URL?, error: Error?) {
        // Note: File operations should be completed before this method exits to ensure the temporary
        // file isn't deleted. Using async here is safe as the completion handlers will manage file moves.
        let completions = self.completions
        let downloadId = self.data.identifier
        log.info("Calling \(completions.count) completion handlers for \(downloadId)")
        
        if url != nil {
            data.finishedDate = Date()
        }
        
        for completion in completions {
            if let url = url {
                completion(.success(url))
            }
            else {
                let finalError = error ?? URLError(.unknown)
                let downloadKitError = DownloadKitError.from(finalError as NSError)
                completion(.failure(downloadKitError))
            }
        }
    }
        
    nonisolated public func urlSession(_ session: Foundation.URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task {
            // Forward the call to correct item, to correctly update progress.
            await didWriteData(bytesWritten: bytesWritten, totalBytesWritten: totalBytesWritten, totalBytesExpectedToWrite: totalBytesExpectedToWrite)
            
            let progressUpdates = await self.progressUpdates
            
            for progressUpdate in progressUpdates {
                // Pass both total bytes written and current progress to update observers
                await progressUpdate(totalBytesWritten, progress?.completedUnitCount ?? 0)
            }
        }
    }
    
    nonisolated public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        Task {
            let finalError = error ?? URLError(.unknown)
            let downloadKitError = DownloadKitError.from(finalError as NSError)
            
            for completion in await self.completions {
                completion(.failure(downloadKitError))
            }
        }
    }
    
    nonisolated public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task {
            guard let error = error else {
                return
            }
            
            let downloadKitError = DownloadKitError.from(error as NSError)
            
            for completion in await self.completions {
                completion(.failure(downloadKitError))
            }
        }
    }
}
