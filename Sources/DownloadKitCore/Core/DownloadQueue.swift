//
//  DownloadQueue.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 28/09/2017.
//  Copyright © 2017 Blub Blub. All rights reserved.
//

import Foundation
import os.log

public struct DownloadRetryContext : Sendable {
    public let failedDownloadable: Downloadable
    public let nextDownloadable: Downloadable
    public let error: Error
}

public protocol DownloadQueueObserver: AnyObject, Sendable {
    /// Called when download task starts downloading.
    /// - Parameters:
    ///   - queue: queue on which the task was enqueued.
    ///   - downloadTask: task that started downloading.
    ///   - processor: processor that is processing download.
    func downloadQueue(_ queue: DownloadQueue, downloadDidStart downloadTask: DownloadTask, downloadable: Downloadable, on processor: DownloadProcessor) async
    
    /// Called when download task transfers data.
    /// - Parameters:
    ///   - queue: queue on which the task was enqueued.
    ///   - downloadTask: task that transferred data.
    ///   - processor: processor that is processing download.
    func downloadQueue(_ queue: DownloadQueue, downloadDidTransferData downloadTask: DownloadTask, downloadable: Downloadable, using processor: DownloadProcessor) async
    
    /// Called when the download task finishes downloading. URL is provided as a parameter.
    /// - Parameters:
    ///   - queue: queue on which the task was downloaded.
    ///   - downloadTask: task that finished downloading.
    ///   - location: where on the filesystem the file was stored.
    func downloadQueue(_ queue: DownloadQueue, downloadDidFinish downloadTask: DownloadTask, downloadable: Downloadable, to location: URL) async throws
    
    /// Called when download had actually failed for any reason, including sessions being invalidated. No more retries happen after this call.
    /// - Parameters:
    ///   - queue: queue on which the item was downloaded.
    ///   - downloadTask: task that failed to download.
    ///   - error: error describing the failure.
    func downloadQueue(_ queue: DownloadQueue, downloadDidFail downloadTask: DownloadTask, with error: Error) async
    
    /// Called when download had failed for any reason, but will still retry due to MirrorPolicy providing another downloadable.
    /// - Parameters:
    ///   - queue: queue on which the task was downloaded.
    func downloadQueue(_ queue: DownloadQueue, downloadWillRetry downloadTask: DownloadTask, context: DownloadRetryContext) async
}


public protocol DownloadQueuable : Sendable {
    var isActive: Bool { get async }
    
    var downloads: [DownloadTask] { get async }
    var currentDownloads: [DownloadTask] { get async }
    var queuedDownloads: [DownloadTask] { get async }
    
    var currentDownloadCount: Int { get async }
    var queuedDownloadCount: Int { get async }
    
    func hasDownload(for identifier: String) async -> Bool
    
    func download(for identifier: String) async -> DownloadTask?
    
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
    public var retried = 0
    public var completed = 0
    
    public init() {}
}

extension DownloadQueueMetrics : CustomStringConvertible {
    public var description: String {
        return String(format: "Processed: %d Failed: %d Retried: %d Completed: %d", processed, failed, retried, completed)
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
    private var downloadQueue = [DownloadTask]()
    
    public private(set) var downloadProcessors: [DownloadProcessor] = []
    
    private var notificationCenter = NotificationCenter.default
    
    /// Holds properties to current items for quick access.
    private var progressDownloadMap = Dictionary<String, DownloadTask>()
    private var queuedDownloadMap = Dictionary<String, DownloadTask>()
        
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
    
    public var downloads: [DownloadTask] {
        var values = [DownloadTask]()
        values += Array(progressDownloadMap.values)
        values += Array(downloadQueue)
        
        return values
    }
    
    public var currentDownloads: [DownloadTask] {
        return Array(progressDownloadMap.values)
    }
    
    public var queuedDownloads: [DownloadTask] {
        return Array(downloadQueue)
    }
            
    // MARK: - Iniitialization
    
    public init(processors: [DownloadProcessor] = [], simultaneousDownloads: Int = 20) {
        self.simultaneousDownloads = max(1, simultaneousDownloads)
        downloadProcessors.append(contentsOf: processors)
    }
        
    // MARK: - Public Methods
    
    public func enqueuePending() async {
        for downloadProcessor in downloadProcessors {
            await assignObserverIfNeeded(processor: downloadProcessor)
            await downloadProcessor.enqueuePending()
        }
    }
    
    public func add(processor: DownloadProcessor) async {
        await assignObserverIfNeeded(processor: processor)
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
        
        self.downloadQueue.removeAll()
        self.queuedDownloadMap = [:]
    }
    
    public func cancel(items: [DownloadTask]) async {
        for item in items {
            await cancel(with: item.id)
        }
    }
    
    public func cancel(with identifier: String) async {
        if let downloadableInProgress = self.progressDownloadMap[identifier] {
            await downloadableInProgress.cancel()
            self.progressDownloadMap[identifier] = nil
        }
        else {
            let queuedDownloadable = self.queuedDownloadMap[identifier]
            
            if let index = downloadQueue.firstIndex(where: { $0 === queuedDownloadable }) {
                downloadQueue.remove(at: index)
            }
            else {
                log.fault("DownloadQueue - Error removing downloadable, inconsistent state: \(identifier)")
            }
            
            self.queuedDownloadMap[identifier] = nil
        }
    }
    
    public func hasDownload(for identifier: String) -> Bool {
        return download(for: identifier) != nil
    }
    
    public func download(for identifier: String) -> DownloadTask? {
        progressDownloadMap[identifier] ?? queuedDownloadMap[identifier]
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
    
    public func download(_ downloads: [DownloadTask]) async {
        for item in downloads {
            await download(item)
        }
    }
    
    public func download(_ downloadTask: DownloadTask) async {
        let identifier = downloadTask.id
        // If item is in incomplete state
        // If the item is already in progress, do nothing.
        guard self.progressDownloadMap[identifier] == nil else {
            log.debug("DownloadQueue - Already being downloaded: \(identifier). Ignoring.")
            await self.process()
            return
        }
        
        let previousItem = self.queuedDownloadMap[identifier]
        if previousItem != nil {
            // item is already queued and priorities are the same, do nothing
            await self.process()
            return
        }
        
        log.debug("DownloadQueue - Start Enqueue: \(identifier)")
        
        downloadQueue.append(downloadTask)
        
        log.debug("DownloadQueue - Finished Enqueued: \(identifier)")
                
        self.queuedDownloadMap[identifier] = downloadTask
        await self.process()
    }
    
    // MARK: - Private Methods
    fileprivate func download(for downloadable: Downloadable) async -> DownloadTask? {
        //
        // This method should be used internally to get DownloadTask for specific downloadable
        //
        
        for currentDownload in downloads {
            if let currentDownloadable = await currentDownload.downloadable(with: nil, error: nil), currentDownloadable === downloadable {
                return currentDownload
            }
        }
        
        let downloadableIdentifier = await downloadable.identifier
        log.warning("DownloadQueue - Could not find DownloadTask for downloadable: \(downloadableIdentifier)")
        
        return nil
    }
    
    /// Start processing items, may only be called on process queue.
    private func process() async {
        // If the download queue is not active, quit here.
        guard isActive else {
            return
        }
        
        log.debug("DownloadQueue - Started processing, item count: \(self.progressDownloadMap.count)")
                
        // Process up to X simultaneous downloads.
        while self.progressDownloadMap.count < self.simultaneousDownloads {
            if let task = self.downloadQueue.first {
                // Update state of the queue
                
                self.progressDownloadMap[task.id] = task
                self.queuedDownloadMap[task.id] = nil
            
                _ = self.downloadQueue.removeFirst()
                
                // Grab the first downloadable and start processing the download
                if let downloadable = await task.downloadable(with: nil, error: nil) {
                    await process(download: task, downloadable: downloadable)
                }
                else {
                    // Generally we should never enter here, as this error should be handled by the callbacks and error would be
                    // the error from last retry.
                    await task.complete(with: DownloadQueueError.mirrorsExhausted)
                    self.progressDownloadMap[task.id] = nil
                    
                    log.error("DownloadQueue - Attempting to process download, but no downloadable was returned: \(task.id)")
                }
            }
            else {
                log.debug("DownloadQueue - Empty queue, stopping processing")
                break
            }
        }
        
        log.debug("DownloadQueue - Finished processing, item count: \(self.progressDownloadMap.count)")
    }
    
    /// Process one specific item, will update internal state.
    /// - Parameter item: to process
    private func process(download: DownloadTask, downloadable: Downloadable) async {
        let downloadableIdentifier = await downloadable.identifier
        
        log.debug("DownloadQueue - started processing: \(download.id) provided downloadable: \(downloadableIdentifier)")
                
        // Remove item from queued downloads map.
        
        // Find a processor that will take care of the item.
        if let processor = await findProcessor(for: downloadable) {
            await assignObserverIfNeeded(processor: processor)
            
            log.debug("DownloadQueue - processor will start processing item: \(download.id) downloadable: \(downloadableIdentifier)")
            
            await processor.process(downloadable)
        }
        else {
            // We cannot EVER process this item! We will add it to incomplete, since it just
            // cannot be done.
            log.fault("DownloadQueue - Cannot process the task: \(download.id)")
            
            let error = DownloadKitError.downloadQueue(.noProcessorAvailable(download.id))
            
            await self.observer?.downloadQueue(self, downloadDidFail: download, with: error)
            self.notificationCenter.post(name: DownloadQueue.downloadErrorNotification, object: error, userInfo: [ "downloadItem": downloadable])
        }
        
        log.info("Metrics: \(self.metrics.description) - Processing item: \(download.id)")
    }
    
    private func findProcessor(for downloadable: Downloadable) async -> DownloadProcessor? {
        for processor in self.downloadProcessors {
            if await processor.canProcess(downloadable: downloadable) {
                return processor
            }
        }
        
        return nil
    }
    
    private func assignObserverIfNeeded(processor: DownloadProcessor) async {
        if await processor.observer !== self {
            await processor.set(observer: self)
        }
    }
}

extension DownloadQueue: DownloadProcessorObserver {
    public func downloadDidTransferData(_ processor: DownloadProcessor, downloadable: Downloadable) {
        Task {
            guard let downloadTask = await self.download(for: downloadable) else {
                let downloadableIdentifier = await downloadable.identifier
                log.error("DownloadQueue - Received downloadDidTransferData callback for a Downloadable that is not in queue: \(downloadableIdentifier)")
                return
            }
            
            await self.observer?.downloadQueue(self, downloadDidTransferData: downloadTask, downloadable: downloadable, using: processor)
        }
    }

    public func downloadDidBegin(_ processor: DownloadProcessor, downloadable: Downloadable) {
        Task {
            guard let downloadTask = await self.download(for: downloadable) else {
                let downloadableIdentifier = await downloadable.identifier
                log.error("DownloadQueue - Received downloadDidBegin callback for a Downloadable that is not in queue: \(downloadableIdentifier)")
                return
            }
            
            await self.observer?.downloadQueue(self, downloadDidStart: downloadTask, downloadable: downloadable, on: processor)
            self.notificationCenter.post(name: DownloadQueue.downloadDidStartNotification, object: downloadable)
        }
    }
    
    public func downloadDidStartTransfer(_ processor: DownloadProcessor, downloadable: Downloadable) {
        Task {
            guard let downloadTask = await self.download(for: downloadable) else {
                let downloadableIdentifier = await downloadable.identifier
                log.error("DownloadQueue - Received downloadDidStartTransfer callback for a Downloadable that is not in queue: \(downloadableIdentifier)")
                return
            }
            self.notificationCenter.post(name: DownloadQueue.downloadDidStartTransferNotification, object: downloadTask)
        }
        
    }
    
    public func downloadDidFinishTransfer(_ processor: DownloadProcessor, downloadable: Downloadable, to url: URL) {
        // Need to call this on current thread, as URLSession will remove file behind URL after run-loop.
        // We can move the file in the WebDownloadProcessor, but either way, or decide later in the
        // resource manager.
        Task {
            guard let downloadTask = await self.download(for: downloadable) else {
                let downloadableIdentifier = await downloadable.identifier
                log.error("DownloadQueue - Received downloadDidFinishTransfer callback for a Downloadable that is not in queue: \(downloadableIdentifier)")
                return
            }
            
            do {
                self.progressDownloadMap[downloadTask.id] = nil
                
                self.metrics.processed += 1
                self.metrics.completed += 1
                
                try await observer?.downloadQueue(self, downloadDidFinish: downloadTask, downloadable: downloadable, to: url)
                notificationCenter.post(name: DownloadQueue.downloadDidFinishNotification, object: downloadTask)
                
                // Continue processing downloads.
                
                await self.process()
            }
            catch {
                await retry(downloadTask: downloadTask, downloadable: downloadable, with: error)
            }
        }
    }
    
    public func downloadDidError(_ processor: DownloadProcessor, downloadable: Downloadable, error: Error) {
        Task {
            guard let downloadTask = await self.download(for: downloadable) else {
                let downloadableIdentifier = await downloadable.identifier
                log.error("DownloadQueue - Received downloadDidError callback for a Downloadable that is not in queue: \(downloadableIdentifier)")
                return
            }
            
            await retry(downloadTask: downloadTask, downloadable: downloadable, with: error)
        }
    }
    
    public func downloadDidFinish(_ processor: DownloadProcessor, downloadable: Downloadable) {
        // Currently NO-OP as it is not needed for web, we've done everything in Finish Transfer already
    }
    
    private func retry(downloadTask: DownloadTask, downloadable: Downloadable, with error: Error) async {
        
        
        // Try to get a new downloadable from task.
        
        if let newDownloadable = await downloadTask.downloadable(with: downloadable, error: error) {
            // We can process new downloadable now.
            
            let context = DownloadRetryContext(failedDownloadable: downloadable, nextDownloadable: newDownloadable, error: error)
            
            await observer?.downloadQueue(self, downloadWillRetry: downloadTask, context: context)
            
            self.metrics.retried += 1
            await process(download: downloadTask, downloadable: newDownloadable)
        }
        else {
            await downloadFailure(downloadTask: downloadTask, downloadable: downloadable, withError: error)
        }
    }
    
    private func downloadFailure(downloadTask: DownloadTask, downloadable: Downloadable, withError error: Error) async {
        
        self.metrics.processed += 1
        self.metrics.failed += 1
        
        self.progressDownloadMap[downloadTask.id] = nil
        
        self.notificationCenter.post(name: DownloadQueue.downloadErrorNotification, object: error, userInfo: [ "downloadTask": downloadTask])
        await self.observer?.downloadQueue(self, downloadDidFail: downloadTask, with: error)
        
        await self.process()
    }
}
