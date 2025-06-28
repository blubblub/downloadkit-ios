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
    private var queuedItems: [CloudKitDownload] = []
    
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
    public func set(delegate: (any DownloadProcessorDelegate)?) {
        self.delegate = delegate
    }
    
    public func canProcess(downloadable: Downloadable) -> Bool {
        return downloadable is CloudKitDownload && isActive
    }
    
    public func process(_ downloadable: Downloadable) async {
        guard let item = downloadable as? CloudKitDownload else {
            fatalError("CloudKitDownloadProcessor: Cannot process the unsupported download type. Item: \(downloadable)")
        }
        
        // Fetch CloudKit Record
        guard await item.recordID != nil else {
            await self.delegate?.downloadDidError(self, downloadable: downloadable, error: CloudKitError.noRecord)
            return
        }
        
        let identifier = await downloadable.identifier
        log.info("Enqueued item: \(identifier)")
        
        self.queuedItems.append(item)
        // Schedule Fetch Timer, which will fetch some records.
        if self.throttlingProtectionEnabled {
            self.fetchWorkItem?.cancel()
            
            let workItem = DispatchWorkItem {
                Task {
                    self.log.info("Fetch timer executed.")
                    await self.fetch()
                }
            }
            
            self.processQueue.asyncAfter(deadline: .now() + self.fetchThrottleTimeout, execute: workItem)
            
            self.fetchWorkItem = workItem
        }
        else {
            // If no protection, fetch immediately!
            await self.fetch()
        }
    }
    
    // MARK: - Private Methods
    private func fetch() async {
        
        let currentItems = self.queuedItems
        self.queuedItems.removeAll()
        
        guard currentItems.count > 0 else {
            self.log.warning("No items currently in queue. Why was I called?")
            
            return
        }
        
        //log.info("Downloading items in batch: \(currentItems.map({ $0.identifier }).joined(separator: ", "))")
        
        // Build map of current items.
        var currentRecordMap : [CKRecord.ID : CloudKitDownload] = [:]
        
        for item in currentItems {
            if let recordID = await item.recordID {
                currentRecordMap[recordID] = item
            }
        }
        
        let recordMap = currentRecordMap
        
        let fetchOperation = CKFetchRecordsOperation(recordIDs: Array(recordMap.keys))

        
        fetchOperation.perRecordProgressBlock = { @Sendable [weak self] recordID, progress in
            Task { @MainActor in
                guard let self = self else { return }
                guard let item = recordMap[recordID] else { return }
                
                let itemProgress = await item.progress
                
                if itemProgress == nil {
                    await self.delegate?.downloadDidStartTransfer(self, downloadable: item)
                }
                
                // Progress report
                await item.update(progress: progress)
                
                // Update delegate
                await self.delegate?.downloadDidTransferData(self, downloadable: item)
            }
        }
        
        fetchOperation.perRecordCompletionBlock = { @Sendable [weak self] record, recordID, error in
            Task { @MainActor in
                guard let self = self, let recordID = recordID else { return }
                guard let item = recordMap[recordID] else { return }
                
                await item.finish()
                
                if let error = error {
                    await self.delegate?.downloadDidError(self, downloadable: item, error: error)
                    return
                }
                
                // Find file asset in record.
                guard
                    let record = record,
                    let asset = record.allKeys().compactMap({ record[$0] as? CKAsset }).first,
                    let url = asset.fileURL
                else {
                    await self.delegate?.downloadDidError(self, downloadable: item, error: CloudKitError.noAssetData)
                    
                    return
                }
                
                if let urlResourceKeys = try? url.resourceValues(forKeys: [.totalFileSizeKey]), let totalBytes = urlResourceKeys.totalFileSize {
                    await item.update(totalBytes: Int64(totalBytes))
                }
                
                await self.delegate?.downloadDidFinishTransfer(self, downloadable: item, to: url)
            }
            
        }
        
        // Run all start and on delegate.
        for item in currentItems {
            await item.start(with: [:])
            await self.delegate?.downloadDidBegin(self, downloadable: item)
        }
        
        self.database.add(fetchOperation)
    }
    
    public func pause() {
        
    }
    
    public func resume() {
        
    }
    
    public func enqueuePending() async {
        // TODO: Resume previous CloudKit downloads from database, which is likely not possible directly.
    }
}
