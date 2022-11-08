//
//  DownloadProcessor.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 10/30/20.
//

import Foundation

public protocol DownloadProcessor: AnyObject {
    var isActive: Bool { get }
    var delegate: DownloadProcessorDelegate? { get set }

    func canProcess(item: Downloadable) -> Bool
    func process(_ item: Downloadable)
    
    /// If DownloadProcessor has any pending downloads left.
    func enqueuePending(completion: (() -> Void)?)
    
    /// Pause and resume DownloadProcessor.
    func pause()
    func resume()
}

public protocol DownloadProcessorDelegate: AnyObject {
    /// Sent when a Downloadable is being worked on.
    func downloadDidBegin(_ processor: DownloadProcessor, item: Downloadable)
    
    /// Sent when a Downloadable starts transferring data.
    func downloadDidStartTransfer(_ processor: DownloadProcessor, item: Downloadable)
    
    /// Sent when a Downloadable did receive some data.
    func downloadDidTransferData(_ processor: DownloadProcessor, item: Downloadable)
    
    /// Sent when a Downloadable fails for any reason.
    func downloadDidError(_ processor: DownloadProcessor, item: Downloadable, error: Error)
    
    /// Sent when a Downloadable finishes transferring data.
    func downloadDidFinishTransfer(_ processor: DownloadProcessor, item: Downloadable, to url: URL)
    
    /// Sent when a Downloadable is completely finished.
    func downloadDidFinish(_ processor: DownloadProcessor, item: Downloadable)
}
