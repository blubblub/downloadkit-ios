//
//  CloudKitDownloadProcessor.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 2/5/21.
//

import CloudKit
import Foundation
import os

public enum CloudKitError: Error {
    case noAssetData
    case noRecord
}

public actor CloudKitDownloadProcessor: DownloadProcessor {
    
    // MARK: - Private Properties
    private let processQueue = DispatchQueue(label: "downloadkit.cloudkit.process-queue",
                                             qos: .background)
    private var fetchWorkItem: DispatchWorkItem? = nil
    private var queuedItems: [CloudKitDownloadItem] = []
    
    private let fetchThrottleTimeout: TimeInterval = 0.5
    
    // MARK: - Public Properties
    public let log = Logger(subsystem: "org.blubblub.downloadkit.cloudkit", category: "CloudKitProcessor")
    
    public var database: CKDatabase
    
    public var isActive = true
    
    public var throttlingProtectionEnabled = true
    
    public weak var delegate: DownloadProcessorDelegate?
    
    // MARK: - Initialization
    init() {
        self.init(database: CKContainer.default().publicCloudDatabase)
    }
    
    init(container: CKContainer) {
        self.init(database: container.publicCloudDatabase)
    }
    
    public init(database: CKDatabase) {
        self.database = database
    }
    
    // MARK: - DownloadProcessor
    public func canProcess(item: Downloadable) -> Bool {
        return item is CloudKitDownloadItem && isActive
    }
    
    public func process(_ item: Downloadable) {
        let itemDescription = item.description
        
        guard let item = item as? CloudKitDownloadItem else {
            fatalError("CloudKitDownloadProcessor: Cannot process the unsupported download type. Item: \(itemDescription)")
        }
        
        // Fetch CloudKit Record
        guard item.recordID != nil else {
            self.delegate?.downloadDidError(self, item: item, error: CloudKitError.noRecord)
            return
        }
        
        log.info("Enqueued item: \(item.identifier)")
        
        self.queuedItems.append(item)
        // Schedule Fetch Timer, which will fetch some records.
        if self.throttlingProtectionEnabled {
            self.fetchWorkItem?.cancel()
            
            let workItem = DispatchWorkItem {
                
                self.log.info("Fetch timer executed.")
                self.fetch()
            }
            
            self.processQueue.asyncAfter(deadline: .now() + self.fetchThrottleTimeout, execute: workItem)
            
            self.fetchWorkItem = workItem
        }
        else {
            // If no protection, fetch immediately!
            self.fetch()
        }
    }
    
    // MARK: - Private Methods
    private func fetch() {
        
        let currentItems = self.queuedItems
        self.queuedItems.removeAll()
        
        guard currentItems.count > 0 else {
            self.log.warning("No items currently in queue. Why was I called?")
            
            return
        }
        
        log.info("Downloading items in batch: \(currentItems.map({ $0.identifier }).joined(separator: ", "))")
        
        // Build map of current items.
        var recordMap : [CKRecord.ID : CloudKitDownloadItem] = [:]
        
        for item in currentItems {
            if let recordID = item.recordID {
                recordMap[recordID] = item
            }
        }
        
        let fetchOperation = CKFetchRecordsOperation(recordIDs: Array(recordMap.keys))
        
        fetchOperation.perRecordProgressBlock = { [weak self] recordID, progress in
            guard let self = self else { return }
            guard let item = recordMap[recordID] else { return }
            
            if !item.didSendStartTransferNotification {
                item.didSendStartTransferNotification = true
                Task {
                    await self.delegate?.downloadDidStartTransfer(self, item: item)
                }
            }
            
            // Progress report
            item.update(progress: progress)
            
            // Update delegate
            Task {
                await self.delegate?.downloadDidTransferData(self, item: item)
            }
        }
        
        fetchOperation.perRecordCompletionBlock = { [weak self] record, recordID, error in
            guard let self = self, let recordID = recordID else { return }
            guard let item = recordMap[recordID] else { return }
            
            item.finish()
            
            if let error = error {
                Task {
                    await self.delegate?.downloadDidError(self, item: item, error: error)
                }
                return
            }
            
            // Find file asset in record.
            guard
                let record = record,
                let asset = record.allKeys().compactMap({ record[$0] as? CKAsset }).first,
                let url = asset.fileURL
            else {
                Task {
                    await self.delegate?.downloadDidError(self, item: item, error: CloudKitError.noAssetData)
                }
                return
            }
            
            if let urlResourceKeys = try? url.resourceValues(forKeys: [.totalFileSizeKey]), let totalBytes = urlResourceKeys.totalFileSize {
                item.totalBytes = Int64(totalBytes)
            }
            
            Task {
                await self.delegate?.downloadDidFinishTransfer(self, item: item, to: url)
            }
            
        }
        
        // Run all start and on delegate.
        currentItems.forEach { item in
            item.start(with: [:])
            self.delegate?.downloadDidBegin(self, item: item)
        }
        
        self.database.add(fetchOperation)
    }
    
    public func pause() {
        
    }
    
    public func resume() {
        
    }
    
    public func enqueuePending(completion: (() -> Void)?) {
        // TODO: Resume previous CloudKit downloads from database, which is likely not possible directly.
    }
}
