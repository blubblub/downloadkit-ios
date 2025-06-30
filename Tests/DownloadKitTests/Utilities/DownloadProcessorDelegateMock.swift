//
//  DownloadProcessorDelegateMock.swift
//  BlubBlubCore_Example
//
//  Created by Dal Rupnik on 2/11/21.
//  Copyright © 2021 Blub Blub. All rights reserved.
//
import DownloadKit
import Foundation

actor DownloadProcessorDelegateMock: DownloadProcessorDelegate {
    var beginCallback: (() -> Void)?
    var startTransferCallback: (() -> Void)?
    var errorCallback: ((Error) -> Void)?
    var finishTransferCallback: ((URL) -> Void)?
    var finishCallback: (() -> Void)?
    
    func setBeginCallback(_ callback: @escaping () -> Void) {
        beginCallback = callback
    }
    
    func setStartTransferCallback(_ callback: @escaping () -> Void) {
        startTransferCallback = callback
    }
    
    func setErrorCallback(_ callback: @escaping (Error) -> Void) {
        errorCallback = callback
    }
    
    func setFinishTransferCallback(_ callback: @escaping (URL) -> Void) {
        finishTransferCallback = callback
    }
    
    func setFinishCallback(_ callback: @escaping () -> Void) {
        finishCallback = callback
    }
    
    func downloadDidBegin(_ processor: DownloadProcessor, downloadable: Downloadable) {
        beginCallback?()
    }
    
    // Should be sent when a Downloadable starts transferring data.
    func downloadDidStartTransfer(_ processor: DownloadProcessor, downloadable: Downloadable) {
        startTransferCallback?()
    }
    
    // Should be sent when a Downloadable fails for any reason.
    func downloadDidError(_ processor: DownloadProcessor, downloadable: Downloadable, error: Error) {
        errorCallback?(error)
    }
    
    // Should be sent when a Downloadable finishes transferring data.
    func downloadDidFinishTransfer(_ processor: DownloadProcessor, downloadable: Downloadable, to url: URL) {
        finishTransferCallback?(url)
    }
    
    // Should be sent when a Downloadable is completely finished.
    func downloadDidFinish(_ processor: DownloadProcessor, downloadable: Downloadable) {
        finishCallback?()
    }

    func downloadDidTransferData(_ processor: any DownloadKit.DownloadProcessor, downloadable: any DownloadKit.Downloadable) {
    }
   
}
