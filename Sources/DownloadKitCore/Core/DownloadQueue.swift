//
//  DownloadQueue.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 28/09/2017.
//  Copyright © 2017 Blub Blub. All rights reserved.
//

import Foundation
import os.log

public protocol DownloadQueueObserver: Actor {
    /// Called when download item starts downloading.
    /// - Parameters:
    ///   - queue: queue on which the item was enqueued.
    ///   - item: item that started downloading.
    ///   - processor: processor that is processing download.
    func downloadQueue(_ queue: DownloadQueue, downloadDidStart downloadable: Downloadable, with processor: DownloadProcessor) async
    
    /// Called when download item transfers data.
    /// - Parameters:
    ///   - queue: queue on which the item was enqueued.
    ///   - item: item that transferred data.
    ///   - processor: processor that is processing download.
    func downloadQueue(_ queue: DownloadQueue, downloadDidTransferData downloadable: Downloadable, using processor: DownloadProcessor) async
    
    /// Called when the download item finishes downloading. URL is provided as a parameter.
    /// - Parameters:
    ///   - queue: queue on which the item was downloaded.
    ///   - item: item that finished downloading.
    ///   - location: where on the filesystem the file was stored.
    func downloadQueue(_ queue: DownloadQueue, downloadDidFinish downloadable: Downloadable, to location: URL) async throws
    
    /// Called when download had failed for any reason, including sessions being invalidated.
    /// - Parameters:
    ///   - queue: queue on which the item was downloaded.
    ///   - item: item that failed to download.
    ///   - error: error describing the failure.
    func downloadQueue(_ queue: DownloadQueue, downloadDidFail downloadable: Downloadable, with error: Error) async
}


public protocol DownloadQueuable : Actor {
    var isActive: Bool { get async }
    
    var downloads: [Downloadable] { get async }
    var currentDownloads: [Downloadable] { get async }
    var queuedDownloads: [Downloadable] { get async }
    
    var currentDownloadCount: Int { get async }
    var queuedDownloadCount: Int { get async }
    
    func hasDownloadable(with identifier: String) async -> Bool
    
    func downloadable(for identifier: String) async -> Downloadable?
    
    func isDownloading(for identifier: String) async -> Bool
    
    func setActive(_ value: Bool) async
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

public struct DownloadQueueMetrics: Sendable {
    public var processed = 0
    public var failed = 0
    public var completed = 0
    
    public init() {}
}

extension DownloadQueueMetrics : CustomStringConvertible {
    public var description: String {
        return String(format: "Processed: %d Failed: %d Retried: %d Completed: %d", processed, failed, 0, completed)
    }
}

///
/// DownloadQueue to process Downloadable items. It's main purpose is to handle different prioritizations,
/// and redirect downloadables to several processors.
///
public actor DownloadQueue: DownloadQueuable {
        
    // MARK: - Private Properties
    
    private let log = Logger.logDownloadQueue
    
    /// Holds pending downloads.
    private var downloadQueue = AsyncPriorityQueue<Downloadable>()
    
    public private(set) var downloadProcessors: [DownloadProcessor] = []
    
    private var notificationCenter = NotificationCenter.default
    
    /// Holds properties to current items for quick access.
    private var progressDownloadMap = Dictionary<String, Downloadable>()
    private var queuedDownloadMap = Dictionary<String, Downloadable>()
        
    // MARK: - Public Properties
    
    public private(set) weak var observer: DownloadQueueObserver?
    public func set(observer: DownloadQueueObserver?) {
        self.observer = observer
    }
    
    public private(set) var simultaneousDownloads = 20
    public func set(simultaneousDownloads: Int) {
        self.simultaneousDownloads = max(1, simultaneousDownloads)
    }
    
    public private(set) var metrics = DownloadQueueMetrics()
    
    /// Set to false to stop any further downloads.
    public var isActive = true {
        didSet {
            if isActive {
                Task {
                    await self.process()
                }
            }
        }
    }
    
    public var downloads: [Downloadable] {
        var values = [Downloadable]()
        values += Array(progressDownloadMap.values)
        values += Array(downloadQueue)
        
        return values
    }
    
    public var currentDownloads: [Downloadable] {
        return Array(progressDownloadMap.values)
    }
    
    public var queuedDownloads: [Downloadable] {
        return Array(downloadQueue)
    }
    
    public var currentMaximumPriority : Int {
        get async {
            return await downloadQueue.first?.priority ?? 0
        }
    }
        
    // MARK: - Iniitialization
    
    public init() {
        downloadQueue.order = { await $0.priority > $1.priority }
    }
        
    // MARK: - Public Methods
    
    public func enqueuePending() async {
        for downloadProcessor in downloadProcessors {
            await downloadProcessor.enqueuePending()
        }
    }
    
    public func add(processor: DownloadProcessor) async {
        await processor.set(observer: self)
        downloadProcessors.append(processor)
    }
    
    /// Will cancel all current transfers.
    public func cancelCurrentDownloads() async {
        for item in self.progressDownloadMap.values {
            await item.cancel()
        }
        
        self.progressDownloadMap = [:]
    }
    
    public func cancelAll() async {
        // Cancel current downloads.
        await cancelCurrentDownloads()
        
        for item in self.downloadQueue {
            await item.cancel()
        }
        
        self.downloadQueue.clear()
        self.queuedDownloadMap = [:]
    }
    
    public func cancel(items: [Downloadable]) async {
        for item in items {
            await cancel(with: item.identifier)
        }
    }
    
    public func cancel(with identifier: String) async {
        if let downloadableInProgress = self.progressDownloadMap[identifier] {
            await downloadableInProgress.cancel()
            self.progressDownloadMap[identifier] = nil
        }
        else {
            self.queuedDownloadMap[identifier] = nil
            
            var downloadQueueCopy = self.downloadQueue
            
            await downloadQueueCopy.remove(where: { downloadable in
                return await downloadable.identifier == identifier
            })
            
            self.downloadQueue = downloadQueueCopy
        }
    }
    
    public func hasDownloadable(with identifier: String) -> Bool {
        return downloadable(for: identifier) != nil
    }
    
    public func downloadable(for identifier: String) -> Downloadable? {
        progressDownloadMap[identifier] ?? queuedDownloadMap[identifier]
    }
    
    public func isDownloading(_ downloadable: Downloadable) async -> Bool {
        return isDownloading(for: await downloadable.identifier)
    }
    
    public func isDownloading(for identifier: String) -> Bool {
        return progressDownloadMap[identifier] != nil
    }
    
    public var currentDownloadCount: Int {
        return currentDownloads.count
    }
    
    public var queuedDownloadCount: Int {
        return queuedDownloads.count
    }
    
    public func setActive(_ value: Bool) async {
        self.isActive = value
    }
    
    public func download(_ downloadable: [Downloadable]) async {
        for item in downloadable {
            await download(item)
        }
    }
    
    public func download(_ downloadable: Downloadable) async {
        let identifier = await downloadable.identifier
        // If item is in incomplete state
        // If the item is already in progress, do nothing.
        guard self.progressDownloadMap[identifier] == nil else {
            return
        }
        
        let previousItem = self.queuedDownloadMap[identifier]
        if let previousItem = previousItem, await downloadable.priority > previousItem.priority {
            // If current item priority is higher, remove it and enqueue it again, which will place it higher.
            var downloadQueueCopy = self.downloadQueue
            
            await downloadQueueCopy.remove(where: { item in
                return await item.isEqual(to: previousItem)
            })
            
            self.downloadQueue = downloadQueueCopy
        } else if previousItem != nil {
            // item is already queued and priorities are the same, do nothing
            await self.process()
            return
        }
        
        var downloadQueueCopy = self.downloadQueue
        await downloadQueueCopy.enqueue(downloadable)
        self.downloadQueue = downloadQueueCopy
                
        self.queuedDownloadMap[identifier] = downloadable
        await self.process()
    }
    
    /// Start processing items, may only be called on process queue.
    private func process() async {
        // If the download queue is not active, quit here.
        guard isActive else {
            return
        }
                
        // Process up to X simultaneous downloads.
        while self.progressDownloadMap.count < self.simultaneousDownloads {
            if let item = self.downloadQueue.dequeue() {
                await process(downloadable: item)
            }
            else {
                break
            }
        }
    }
    
    /// Process one specific item, will update internal state.
    /// - Parameter item: to process
    private func process(downloadable: Downloadable) async {
        let identifier = await downloadable.identifier
        
        // Remove item from queued downloads map.
        self.queuedDownloadMap[identifier] = nil
        
        // Find a processor that will take care of the item.
        if let processor = await findProcessor(for: downloadable) {
            
            self.progressDownloadMap[identifier] = downloadable
            await processor.process(downloadable)
            
            Task {
                await self.observer?.downloadQueue(self, downloadDidStart: downloadable, with: processor)
            }
            
            self.notificationCenter.post(name: DownloadQueue.downloadDidStartNotification, object: downloadable)
        }
        else {
            // We cannot EVER process this item! We will add it to incomplete, since it just
            // cannot be done.
            
            let error = DownloadKitError.downloadQueue(.noProcessorAvailable(identifier))
            
            Task {
                await self.observer?.downloadQueue(self, downloadDidFail: downloadable, with: error)
            }
            
            self.notificationCenter.post(name: DownloadQueue.downloadErrorNotification, object: error, userInfo: [ "downloadItem": downloadable])
        }
        
        log.info("Metrics: \(self.metrics.description) - Processing item: \(identifier)")
    }
    
    private func findProcessor(for downloadable: Downloadable) async -> DownloadProcessor? {
        for processor in self.downloadProcessors {
            if await processor.canProcess(downloadable: downloadable) {
                return processor
            }
        }
        
        return nil
    }
}

extension DownloadQueue: DownloadProcessorObserver {
    public func downloadDidTransferData(_ processor: DownloadProcessor, downloadable: Downloadable) {
        Task {
            await self.observer?.downloadQueue(self, downloadDidTransferData: downloadable, using: processor)
        }
    }

    public func downloadDidBegin(_ processor: DownloadProcessor, downloadable: Downloadable) {
        Task {
            let identifier = await downloadable.identifier
            
            if let trackedItem = self.downloadable(for: identifier) {
                // We have the item, but it wasn't processed yet, but a processor decided to start downloading it.
                // This indicates a broken state between processor and the queue and we will fix it here.
                // This could also be a resume of a very old download, if processor has that ability (such as in case of URLSession).
                
                if self.progressDownloadMap[identifier] == nil {
                    log.error("Internal download inconsistency state for: \(identifier)")
                    
                    self.progressDownloadMap[identifier] = trackedItem
                    self.queuedDownloadMap[identifier] = nil
                }
            }
            else {
                // We have no tracked item here, but processor started working on it on it's own.
                // This is to handle any resumed transfers if needed.
                self.progressDownloadMap[identifier] = downloadable
            }
        }
    }
    
    public func downloadDidStartTransfer(_ processor: DownloadProcessor, downloadable: Downloadable) {
        self.notificationCenter.post(name: DownloadQueue.downloadDidStartTransferNotification, object: downloadable)
    }
    
    public func downloadDidFinishTransfer(_ processor: DownloadProcessor, downloadable: Downloadable, to url: URL) {
        // Need to call this on current thread, as URLSession will remove file behind URL after run-loop.
        // We can move the file in the WebDownloadProcessor, but either way, or decide later in the
        // resource manager.
        Task {
            let identifier = await downloadable.identifier
            do {
                try await observer?.downloadQueue(self, downloadDidFinish: downloadable, to: url)
                notificationCenter.post(name: DownloadQueue.downloadDidFinishNotification, object: downloadable)
                
                self.metrics.processed += 1
                self.metrics.completed += 1
                
                self.progressDownloadMap[identifier] = nil
                
                // Continue processing downloads.
                // I'd do this in defer, if it supported async.
                
                await self.process()
            }
            catch {
                // If something goes wrong with file moving.
                self.metrics.failed += 1
                self.metrics.processed += 1
                
                self.progressDownloadMap[identifier] = nil
                
                await self.process()
            }
        }
    }
    
    public func downloadDidError(_ processor: DownloadProcessor, downloadable: Downloadable, error: Error) {
        Task {
            let identifier = await downloadable.identifier
            
            // Call delegate for error.
            // Remove item from current downloads
            self.metrics.processed += 1
            self.metrics.failed += 1
            
            self.progressDownloadMap[identifier] = nil

            self.notificationCenter.post(name: DownloadQueue.downloadErrorNotification, object: error, userInfo: [ "downloadItem": downloadable])
            
            await self.observer?.downloadQueue(self, downloadDidFail: downloadable, with: error)
            
            // Resume processing
            await self.process()
        }
    }
    
    public func downloadDidFinish(_ processor: DownloadProcessor, downloadable: Downloadable) {
        // Currently NO-OP as it is not needed for web, we've done everything in Finish Transfer already
    }
}
