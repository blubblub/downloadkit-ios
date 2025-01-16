//
//  DownloadProcessorDelegateMock.swift
//  BlubBlubCore_Example
//
//  Created by Dal Rupnik on 2/11/21.
//  Copyright © 2021 Blub Blub. All rights reserved.
//
import DownloadKit
import Foundation

class DownloadProcessorDelegateMock: DownloadProcessorDelegate {
    var beginCallback: (() -> Void)?
    var startTransferCallback: (() -> Void)?
    var errorCallback: ((Error) -> Void)?
    var finishTransferCallback: ((URL) -> Void)?
    var finishCallback: (() -> Void)?
    
    func downloadDidBegin(_ processor: DownloadProcessor, item: Downloadable) {
        beginCallback?()
    }
    
    // Should be sent when a Downloadable starts transferring data.
    func downloadDidStartTransfer(_ processor: DownloadProcessor, item: Downloadable) {
        startTransferCallback?()
    }
    
    // Should be sent when a Downloadable fails for any reason.
    func downloadDidError(_ processor: DownloadProcessor, item: Downloadable, error: Error) {
        errorCallback?(error)
    }
    
    // Should be sent when a Downloadable finishes transferring data.
    func downloadDidFinishTransfer(_ processor: DownloadProcessor, item: Downloadable, to url: URL) {
        finishTransferCallback?(url)
    }
    
    // Should be sent when a Downloadable is completely finished.
    func downloadDidFinish(_ processor: DownloadProcessor, item: Downloadable) {
        finishCallback?()
    }

    func downloadDidTransferData(_ processor: any DownloadKit.DownloadProcessor, item: any DownloadKit.Downloadable) {
    }
   
}
