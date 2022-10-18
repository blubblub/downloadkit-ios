//
//  CloudKitDownloadProcessor.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 2/5/21.
//

import CloudKit
import Foundation

public enum CloudKitError: Error {
    case noAssetData
    case noRecord
    case throttled
}

private class Throttler {
    var shouldThrottle = false
    
    var requestLimit = 10
    
    private var inFlight = 0
    private var timer : Timer? = nil
    
    func ping() {
        guard !shouldThrottle else {
            return
        }
        
        inFlight += 1
        
        timer?.invalidate()
                
        timer = Timer.scheduledTimer(timeInterval: 5.0, target: self, selector: #selector(self.reset), userInfo: nil, repeats: false);
        
        if inFlight >= requestLimit {
            shouldThrottle = true
        }
    }
    
    func pong() {
        inFlight -= 1
    }
    
    @objc func reset() {
        shouldThrottle = false
    }
}

public class CloudKitDownloadProcessor: DownloadProcessor {
    
    public var database: CKDatabase
    
    public var isActive = true
    
    public var throttlingProtectionEnabled = true
    
    public weak var delegate: DownloadProcessorDelegate?
    
    private let throttler = Throttler()
    
    convenience init() {
        self.init(database: CKContainer.default().publicCloudDatabase)
    }
    
    convenience init(container: CKContainer) {
        self.init(database: container.publicCloudDatabase)
    }
    
    public init(database: CKDatabase) {
        self.database = database
    }
    
    public func canProcess(item: Downloadable) -> Bool {
        return item is CloudKitDownloadItem && isActive
    }
    
    public func process(_ item: Downloadable) {
        let itemDescription = item.description
        
        guard let item = item as? CloudKitDownloadItem else {
            fatalError("CloudKitDownloadProcessor: Cannot process the unsupported download type. Item: \(itemDescription)")
        }
        
        // Fetch CloudKit Record
        guard let recordID = item.recordID else {
            self.delegate?.downloadDidError(self, item: item, error: CloudKitError.noRecord)
            return
        }
        
        // CloudKit starts limiting the amount of requests per second.
        if throttler.shouldThrottle && throttlingProtectionEnabled {
            self.delegate?.downloadDidError(self, item: item, error: CloudKitError.throttled)
            return
        }
        
        if self.throttlingProtectionEnabled {
            self.throttler.ping()
        }
                
        self.delegate?.downloadDidBegin(self, item: item)
        
        let fetchOperation = CKFetchRecordsOperation(recordIDs: [ recordID ])
        
        var didSendStartTransferNotification = false
        
        fetchOperation.perRecordProgressBlock = { [weak self] recordID, progress in
            guard let self = self else { return }
            
            if !didSendStartTransferNotification {
                didSendStartTransferNotification = true
                self.delegate?.downloadDidStartTransfer(self, item: item)
            }
            
            // Progress report
            item.update(progress: progress)
        }
        
        fetchOperation.perRecordCompletionBlock = { [weak self] record, recordID, error in
            guard let self = self else { return }
            
            item.finish()
            
            // Ping Throttler, so it knows about the request.
            if self.throttlingProtectionEnabled {
                self.throttler.pong()
            }
            
            if let error = error {
                self.delegate?.downloadDidError(self, item: item, error: error)
                return
            }
            
            // Find file asset in record.
            guard
                let record = record,
                let asset = record.allKeys().compactMap({ record[$0] as? CKAsset }).first,
                let url = asset.fileURL
            else {
                self.delegate?.downloadDidError(self, item: item, error: CloudKitError.noAssetData)
                return
            }
            
            if let urlResourceKeys = try? url.resourceValues(forKeys: [.totalFileSizeKey]), let totalBytes = urlResourceKeys.totalFileSize {
                item.totalBytes = Int64(totalBytes)
            }
            
            self.delegate?.downloadDidFinishTransfer(self, item: item, to: url)
        }
        
        item.start(with: [:])
        
        database.add(fetchOperation)
    }
    
    public func pause() {
        
    }
    
    public func resume() {
        
    }
    
    public func enqueuePending(completion: (() -> Void)?) {
        // TODO: Resume previous CloudKit downloads from database, which is likely not possible directly.
    }
}
