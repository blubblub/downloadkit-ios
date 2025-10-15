//
//  DownloadTask.swift
//  DownloadKit
//
//  Created by Dal Rupnik on 09.10.2025.
//

import os.log

private actor DownloadTaskState {
    private var continuation: CheckedContinuation<Void, Error>?
    private var isComplete = false
    fileprivate private(set) var currentDownloadable: Downloadable?
    
    private var error: Error?
    
    private let log = Logger(subsystem: "org.blubblub.downloadkit.request", category: "DownloadState")
    
    public var instanceId: String {
        return "\(ObjectIdentifier(self))"
    }
    
    fileprivate func wait() async throws {
        if isComplete {
            log.debug("Waiting, but the download is already complete: \(self.instanceId)")
            
            // Throw error on wait, if completed.
            if let error = error {
                throw error
            }
            
            return
        }
        
        log.debug("Waiting on continuation for download completion: \(self.instanceId)")
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
        }
        
        log.debug("End of waiting for download completion: \(self.instanceId)")
    }
    
    fileprivate func cancel() async {
        if isComplete {
            log.warning("Cancelled completed task: \(self.instanceId)")
            return
        }
        if let currentDownloadable {
            // We have downloadable, need to cancel it and wait for it to error. (this is expected in URL session)
            await currentDownloadable.cancel()
        }
        else {
            // Download never started, just mark it as completed.
            markComplete(with: DownloadKitError.network(.cancelled))
        }
    }
    
    
    fileprivate func set(downloadable: Downloadable?) {
        currentDownloadable = downloadable
        
        // This happens on redownloading a cancelled or failed task, we should reset the isComplete flah.
        isComplete = false
    }

    fileprivate func markComplete(with error: Error? = nil) {
        if isComplete {
            log.warning("Completing a completed download: \(self.instanceId)")
            // To prevent multiple continuation calls.
            // This happens when a download in-flight is cancelled, as URLSession will call the delegate again.
            return
        }
        
        log.debug("Marking completion of download: \(self.instanceId)")
        
        isComplete = true
        self.error = error
        
        if let error = error {
            continuation?.resume(throwing: error)
        }
        else {
            continuation?.resume()
        }
        
        continuation = nil
        
        log.debug("Marked download as complete: \(self.instanceId)")
    }
}

/// Once download starts processing this class is created to hold state
public final class DownloadTask: Sendable, Equatable {
    private let log = Logger(subsystem: "org.blubblub.downloadkit.manager", category: "DownloadTask")

    private let state: DownloadTaskState
    
    public let request: DownloadRequest
    public let mirrorPolicy: MirrorPolicy
    
    public var id: String {
        request.id
    }
    
    public var instanceId: String {
        return "\(ObjectIdentifier(self))"
    }
    
    public init(request: DownloadRequest, mirrorPolicy: MirrorPolicy) {
        self.request = request
        self.mirrorPolicy = mirrorPolicy
        
        self.state = DownloadTaskState()
    }
    
    // MARK: - Public Functions
    
    public func downloadable() async -> Downloadable? {
        return await state.currentDownloadable
    }
    
    public func createDownloadable(with previousDownloadable: Downloadable?, error: Error?) async -> Downloadable? {
        if previousDownloadable != nil && error == nil {
            log.error("DownloadTask - Inconsistent state, no need to fetch downloadable, if error was nil.")
            return nil
        }
        
        let currentDownloadable = await state.currentDownloadable
        
        // If we already have a downloadable, just return the same one.
        if let currentDownloadable, previousDownloadable == nil, error == nil {
            return currentDownloadable
        }
        
        let failedIdentifier = await previousDownloadable?.identifier
        let downloadable = await mirrorPolicy.downloadable(for: request.resource, lastDownloadableIdentifier: failedIdentifier, error: error)
        await state.set(downloadable: downloadable)
        
        log.debug("DownloadTask - Creating new downloadable: \(self.id) downloadable: \(downloadable != nil ? "YES" : "NO")")
            
        return downloadable
    }
    
    public static func == (lhs: DownloadTask, rhs: DownloadTask) -> Bool {
        return lhs.id == rhs.id
    }
        
    public func waitTillComplete() async throws {
        let stateId = "\(ObjectIdentifier(state))"
        
        log.debug("Waiting for download completion: \(self.id) (\(self.instanceId)-\(stateId)")
        try await state.wait()
    }
    
    // MARK: - Internal Functions
    
    // Do not call these functions outside of DownloadKit
    package func complete(with error: Error? = nil) async {
        let stateId = "\(ObjectIdentifier(state))"
        log.debug("Completing download: \(self.id) (\(self.instanceId)-\(stateId)")
        await state.markComplete(with: error)
    }
    package func cancel() async {
        let stateId = "\(ObjectIdentifier(state))"
        log.debug("Cancelling download: \(self.id) (\(self.instanceId)-\(stateId)")
        await state.cancel()
    }
}
