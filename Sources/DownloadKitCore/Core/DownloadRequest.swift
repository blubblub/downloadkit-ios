//
//  DownloadRequest.swift
//
//  Created by Dal Rupnik on 10/18/22.
//

import Foundation

private actor DownloadRequestState {
    private var continuation: CheckedContinuation<Void, Error>?
    private var isComplete = false
    private var error: Error?

    fileprivate func wait() async throws {
        if isComplete {
            // Throw error on wait, if completed.
            if let error = error {
                throw error
            }
            
            return
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
        }
    }

    fileprivate func markComplete(with error: Error? = nil) {
        if isComplete {
            // To prevent multiple continuation calls.
            // This happens when a download in-flight is cancelled, as URLSession will call the delegate again.
            return
        }
        
        isComplete = true
        self.error = error
        
        if let error = error {
            continuation?.resume(throwing: error)
        }
        else {
            continuation?.resume()
        }
        
        continuation = nil
    }
}

/// Hold references to downloads, so they can be properly handled.
public struct DownloadRequest: Sendable, Equatable {
    
    private let state: DownloadRequestState
    
    public let resource: ResourceFile
    public let options: RequestOptions
    public let mirror: ResourceMirrorSelection
    
    public init(_ request: DownloadRequest, mirror: ResourceMirrorSelection) {
        self.state = request.state
        self.resource = request.resource
        self.options = request.options
        self.mirror = mirror
    }
    
    public init(resource: ResourceFile, options: RequestOptions, mirror: ResourceMirrorSelection) {
        self.state = DownloadRequestState()
        self.resource = resource
        self.options = options
        self.mirror = mirror
    }
    
    public static func == (lhs: DownloadRequest, rhs: DownloadRequest) -> Bool {
        return lhs.id == rhs.id
    }
        
    public var id: String {
        return resource.id
    }
        
    public func downloadableIdentifier() async -> String {
        return await mirror.downloadable.identifier
    }
    
    public func complete(with error: Error? = nil) async {
        await state.markComplete(with: error)
    }
        
    public func waitTillComplete() async throws {
        try await state.wait()
    }
}

/// Returns download selection to retry.
public struct RetryDownloadRequest: Identifiable, Sendable {

    public let nextMirror: ResourceMirrorSelection?
    public let request: DownloadRequest
    
    public init(request: DownloadRequest, nextMirror: ResourceMirrorSelection? = nil) {
        self.nextMirror = nextMirror
        self.request = request
    }
    
    public var id : String {
        return request.id
    }
    
    public func downloadable() async -> Downloadable? {
        
        let nextDownloadable = nextMirror?.downloadable
        
        // Increase priority after download fails, so the next attempt is prioritized higher and
        // not placed at the end of the download queue. We likely want this retry immediately.
        if let currentPriority = await nextDownloadable?.priority {
            await nextDownloadable?.set(priority: currentPriority + 10000)
        }
        
        return nextDownloadable
    }
}
