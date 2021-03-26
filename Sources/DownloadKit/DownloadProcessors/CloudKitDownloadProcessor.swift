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
}

public class CloudKitDownloadProcessor: DownloadProcessor {
    
    public var database: CKDatabase
    
    public var isActive = true
    
    public weak var delegate: DownloadProcessorDelegate?
    
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
