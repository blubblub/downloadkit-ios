//
//  DownloadProcessor.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 10/30/20.
//

import Foundation

public protocol DownloadProcessor: Actor {
    var isActive: Bool { get }
    
    var observer: DownloadProcessorObserver? { get }
    func set(observer: DownloadProcessorObserver?)

    func canProcess(downloadable: Downloadable) -> Bool
    func process(_ downloadable: Downloadable) async
    
    /// If DownloadProcessor has any pending downloads left.
    func enqueuePending() async
    
    /// Pause and resume DownloadProcessor.
    func pause() async
    func resume() async
}

public protocol DownloadProcessorObserver: AnyObject, Actor {
    /// Sent when a Downloadable is being worked on.
    func downloadDidBegin(_ processor: DownloadProcessor, downloadable: Downloadable)
    
    /// Sent when a Downloadable starts transferring data.
    func downloadDidStartTransfer(_ processor: DownloadProcessor, downloadable: Downloadable)
    
    /// Sent when a Downloadable did receive some data.
    func downloadDidTransferData(_ processor: DownloadProcessor, downloadable: Downloadable)
    
    /// Sent when a Downloadable fails for any reason.
    func downloadDidError(_ processor: DownloadProcessor, downloadable: Downloadable, error: Error)
    
    /// Sent when a Downloadable finishes transferring data.
    func downloadDidFinishTransfer(_ processor: DownloadProcessor, downloadable: Downloadable, to url: URL)
    
    /// Sent when a Downloadable is completely finished.
    func downloadDidFinish(_ processor: DownloadProcessor, downloadable: Downloadable)
    
    /// Sent when a background URL session has finished processing all events.
    /// This is important for background app refresh and proper lifecycle management.
    func downloadProcessorDidFinishBackgroundEvents(_ processor: DownloadProcessor)
}

public extension DownloadProcessorObserver {
    /// Default implementation for background events - does nothing by default
    /// Override this method if you need to handle background session completion
    func downloadProcessorDidFinishBackgroundEvents(_ processor: DownloadProcessor) {
        // Default implementation does nothing
    }
}
