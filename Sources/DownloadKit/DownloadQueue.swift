//
//  DownloadQueue.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 28/09/2017.
//  Copyright © 2017 Blub Blub. All rights reserved.
//

import Foundation
import os.log

public protocol DownloadQueueDelegate: class {
    // Called when the download item finishes downloading. URL is provided as a parameter.
    func downloadQueue(_ queue: DownloadQueue, downloadDidFinish item: Downloadable, to location: URL)
    
    // Called when download had failed for any reason, including sessions being invalidated.
    func downloadQueue(_ queue: DownloadQueue, downloadDidFail item: Downloadable, with error: Error)
}


public protocol DownloadQueuable {
    var isActive: Bool { get }
    
    var downloads: [Downloadable] { get }
    var currentDownloads: [Downloadable] { get }
    var queuedDownloads: [Downloadable] { get }
    
    func hasItem(with identifier: String) -> Bool
    
    func item(for identifier: String) -> Downloadable?
    
    func isDownloading(for identifier: String) -> Bool
}

public extension DownloadQueue {
    /// Notification will be sent when a processor starts on a download. After this point the download
    /// could still fail for reasons such as server not being reachable, or connection time out.
    static let downloadDidStartNotification = Notification.Name("DownloadDidStartNotification")
    
    /// Notification will be sent once first bytes are received from the target location.
    /// The download may fail, if something happens with the connection during the transfer,
    /// or device runs out of local disk space.
    static let downloadDidStartTransferNotification = Notification.Name("DownloadDidStartTransferNotification")
    
    /// Download had completed, the URL of the file is in the userInfo object. The URL is only available
    /// on the same thread after notification is received, until it is returned.
    static let downloadDidFinishNotification = Notification.Name("DownloadDidFinishNotification")
    
    /// Download had failed for whatever reason, error will be in user info object.
    static let downloadErrorNotification = Notification.Name("DownloadDidErrorNotification")
}

///
/// DownloadQueue to process Downloadable items. It's main purpose is to handle different prioritizations,
/// and redirect downloadables to several processors.
///
public class DownloadQueue: DownloadQueuable {
    
    
    
    // MARK: - Private Properties
    
    public var log: OSLog = logDK
    
    // Queue that executes after-download operations, such as moving the file.

    private let processQueue = DispatchQueue(label: "org.blubblub.core.synchronization.queue", qos: DispatchQoS.background)
    
    // Holds pending downloads.
    private var downloadQueue = PriorityQueue<Downloadable>(order: { $0.priority > $1.priority })
    
    public private(set) var downloadProcessors: [DownloadProcessor] = []
    
    private var notificationCenter = NotificationCenter.default
    
    // Holds properties to current items for quick access.
    private var progressDownloadMap: [String: Downloadable] = [:]
    private var queuedDownloadMap: [String: Downloadable] = [:]
        
    // MARK: - Public Properties
    
    public weak var delegate: DownloadQueueDelegate?
    public var simultaneousDownloads = 4
    
    // Set to false to stop any further downloads.
    public var isActive = true {
        didSet {
            if isActive {
                processQueue.async {
                    self.process()
                }
            }
        }
    }
    
    public var downloads: [Downloadable] {
        var values: [Downloadable] = []
        
        processQueue.sync {
            values += Array(progressDownloadMap.values)
            values += Array(downloadQueue)
        }
        
        return values
    }
    
    public var currentDownloads: [Downloadable] {
        var values: [Downloadable]! = nil
        
        processQueue.sync {
            values = Array(progressDownloadMap.values)
        }
        
        return values
    }
    
    public var queuedDownloads: [Downloadable] {
        var values: [Downloadable]! = nil
        
        processQueue.sync {
            values = Array(downloadQueue)
        }
        
        return values
    }
    
    /// Returns maximum priority of the items on queue.
    public var currentMaximumPriority: Int {
        return downloadQueue.first?.priority ?? 0
    }
    
    // MARK: - Public Methods
    
    public init () {
    }
    
    public func enqueuePending(completion: (() -> Void)? = nil) {
        downloadProcessors.forEach { $0.enqueuePending(completion: completion) }
    }
    
    public func add(processor: DownloadProcessor) {
        processor.delegate = self
        downloadProcessors.append(processor)
    }
    
    /// Will cancel all current transfers.
    public func cancelCurrentDownloads() {
        processQueue.sync {
            for (_, item) in self.progressDownloadMap {
                item.cancel()
            }
            
            self.progressDownloadMap = [:]
        }
    }
    
    public func cancelAll() {
        // Cancel current downloads.
        cancelCurrentDownloads()
        
        processQueue.sync {
            for item in self.downloadQueue {
                item.cancel()
            }
            
            self.downloadQueue.clear()
        }
    }
    
    public func cancel(items: [Downloadable]) {
        for item in items {
            cancel(with: item.identifier)
        }
    }
    
    public func cancel(with identifier: String) {
        // Check if it is in progress.
        processQueue.sync {
            if let downloadableInProgress = self.progressDownloadMap[identifier] {
                downloadableInProgress.cancel()
                self.progressDownloadMap[identifier] = nil
            }
            else {
                self.queuedDownloadMap[identifier] = nil
                self.downloadQueue.remove(where: { $0.identifier == identifier })
            }
        }
    }
    
    public func hasItem(with identifier: String) -> Bool {
        return progressDownloadMap[identifier] != nil || queuedDownloadMap[identifier] != nil
    }
    
    public func item(for identifier: String) -> Downloadable? {
        return progressDownloadMap[identifier] ?? queuedDownloadMap[identifier]
    }
    
    public func isDownloading(item: Downloadable) -> Bool {
        return isDownloading(for: item.identifier)
    }
    
    public func isDownloading(for identifier: String) -> Bool {
        progressDownloadMap[identifier] != nil
    }
    
    public func download(_ items: [Downloadable]) {
        for item in items {
            download(item)
        }
    }
    
    public func download(_ item: Downloadable) {
        // If item is in incomplete state
        processQueue.sync {
            // If the item is already in progress, do nothing.
            guard self.progressDownloadMap[item.identifier] == nil else {
                self.log.info("[DownloadQueue]: Skipping download request, as it is in progress: %@.", item.identifier)
                return
            }
            
            // If we are pending, we will read the item. This will ensure it's pushed on top.
            var previousItem: Downloadable?
            
            for downloadItem in self.downloadQueue where item.isEqual(to: downloadItem) {
                // Compare identifiers here, as DownloadItem conforms to Comparable, but only compares priorities
                previousItem = downloadItem
                break
            }
            
            // If current item priority is higher, remove it and enqueue it again, which will place it higher.
            if let previousItem = previousItem, item.priority > previousItem.priority {
                self.downloadQueue.remove(where: { $0.isEqual(to: previousItem) })
            }
      
            self.downloadQueue.enqueue(item)
            self.queuedDownloadMap[item.identifier] = item
            
            self.process()
        }
    }
    
    ///
    /// Start processing items, may only be called on process queue.
    ///
    private func process() {
        // Will ensure we do not process anywhere else.
        dispatchPrecondition(condition: .onQueue(processQueue))
        
        // If the download queue is not active, quit here.
        guard isActive else {
            return
        }
                
        // Process up to X simultaneous downloads.
        while self.progressDownloadMap.count < self.simultaneousDownloads {
            if let item = self.downloadQueue.dequeue() {
                process(item: item)
            }
            else {
                break
            }
        }
    }
    
    /// Process one specific item, will update internal state.
    /// - Parameter item: to process
    private func process(item: Downloadable) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        
        // Remove item from queued downloads map.
        self.queuedDownloadMap[item.identifier] = nil
        
        // Find a processor that will take care of the item.
        
        if let processor = downloadProcessors.first(where: { $0.canProcess(item: item) }) {
            
            self.progressDownloadMap[item.identifier] = item
            self.queuedDownloadMap[item.identifier] = nil
            
            processor.process(item)
            
            self.notificationCenter.post(name: DownloadQueue.downloadDidStartNotification, object: item)
        }
        else {
            // We cannot EVER process this item! We will add it to incomplete, since it just
            // cannot be done.
            
            let error = NSError(domain: "org.blubblub.downloadkit", code: -1, userInfo: [ NSLocalizedDescriptionKey: "Cannot process download item, no processor available." ])
            
            self.delegate?.downloadQueue(self, downloadDidFail: item, with: error)
            
            self.notificationCenter.post(name: DownloadQueue.downloadErrorNotification, object: error, userInfo: [ "downloadItem": item])
        }
    }
}

extension DownloadQueue: DownloadProcessorDelegate {

    public func downloadDidBegin(_ processor: DownloadProcessor, item: Downloadable) {
        processQueue.sync {
            if let trackedItem = self.item(for: item.identifier) {
                // We have the item, but it wasn't processed yet, but a processor decided to start downloading it.
                // This indicates a broken state between processor and the queue and we will fix it here.
                // This could also be a resume of a very old download, if processor has that ability (such as in case of URLSession).
                
                if self.progressDownloadMap[item.identifier] == nil {
                    log.error("[DownloadQueue]: Internal download inconsistency state for: %@", item.identifier)
                    
                    self.progressDownloadMap[item.identifier] = trackedItem
                    self.queuedDownloadMap[item.identifier] = nil
                }
            }
            else {
                // We have no tracked item here, but processor started working on it on it's own.
                // This is to handle any resumed transfers if needed.
                log.info("[DownloadQueue]: Processor started to download item %@ from internal state.", item.identifier)
                
                self.progressDownloadMap[item.identifier] = item
            }
        }
    }
    
    public func downloadDidStartTransfer(_ processor: DownloadProcessor, item: Downloadable) {
        self.notificationCenter.post(name: DownloadQueue.downloadDidStartTransferNotification, object: item)
    }
    
    public func downloadDidFinishTransfer(_ processor: DownloadProcessor, item: Downloadable, to url: URL) {
        log.info("[DownloadQueue]: Download complete for id: %@ to: %@", item.identifier, url.absoluteString)
        
        // Need to call this on current thread, as URLSession will remove file behind URL after run-loop.
        // We can move the file in the WebDownloadProcessor, but either way, or decide later in the
        // asset manager.
        
        self.delegate?.downloadQueue(self, downloadDidFinish: item, to: url)
        self.notificationCenter.post(name: DownloadQueue.downloadDidFinishNotification, object: item)
        
        self.processQueue.async {
            self.progressDownloadMap[item.identifier] = nil
            
            // Continue processing downloads.
            self.process()
        }
    }
    
    public func downloadDidError(_ processor: DownloadProcessor, item: Downloadable, error: Error) {
        log.debug("[DownloadQueue] Failed downloading: %@ error: %@", item.identifier, error.localizedDescription)
        
        //item.didComplete(with: error)
        
        // Call delegate for error.
        processQueue.async {
            // Remove item from current downloads
            self.progressDownloadMap[item.identifier] = nil
            
            self.delegate?.downloadQueue(self, downloadDidFail: item, with: error)
 
            self.notificationCenter.post(name: DownloadQueue.downloadErrorNotification, object: error, userInfo: [ "downloadItem": item])
            
            // Continue processing downloadables.
            self.process()
        }
    }
    
    public func downloadDidFinish(_ processor: DownloadProcessor, item: Downloadable) {
        // Currently NO-OP as it is not needed for web, we've done everything in Finish Transfer alre
        log.info("[DownloadQueue]: Download operation for id: %@", item.identifier)
    }
}
