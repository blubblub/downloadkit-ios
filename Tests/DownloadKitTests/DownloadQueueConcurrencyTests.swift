//
//  DownloadQueueConcurrencyTests.swift
//  DownloadKitTests
//
//  Tests for concurrent operations on DownloadQueue including multithreaded
//  enqueueing, cancellation, and state access.
//

import XCTest
import Foundation
@testable import DownloadKit

// MARK: - Mock Downloadable Implementation

/// Mock downloadable that simulates downloads using Thread.sleep()
actor MockDownloadable: Downloadable {
    
    enum State {
        case idle
        case downloading
        case completed
        case failed
        case cancelled
    }
    
    // MARK: - Configuration
    
    private let _identifier: String
    private let delay: TimeInterval
    private let shouldSucceed: Bool
    private let mockFileURL: URL
    
    // MARK: - State
    
    private var state: State = .idle
    private var _startDate: Date?
    private var _finishedDate: Date?
    private var _progress: Foundation.Progress?
    private var _totalBytes: Int64 = 0
    private var _totalSize: Int64 = 1024 * 1024 // 1MB default
    private var _transferredBytes: Int64 = 0
    private var isCancelled = false
    
    // MARK: - Callbacks
    
    var onComplete: ((Result<URL, Error>) -> Void)?
    var onProgress: ((Int64, Int64) -> Void)?
    
    // MARK: - Downloadable Protocol
    
    var identifier: String { _identifier }
    var totalBytes: Int64 { _totalBytes }
    var totalSize: Int64 { _totalSize }
    var transferredBytes: Int64 { _transferredBytes }
    var startDate: Date? { _startDate }
    var finishedDate: Date? { _finishedDate }
    var progress: Foundation.Progress? { _progress }
    
    // MARK: - Initialization
    
    init(identifier: String, delay: TimeInterval, shouldSucceed: Bool, fileURL: URL) {
        self._identifier = identifier
        self.delay = delay
        self.shouldSucceed = shouldSucceed
        self.mockFileURL = fileURL
        self._progress = Foundation.Progress(totalUnitCount: _totalSize)
    }
    
    // MARK: - Public Methods
    
    func start(with parameters: DownloadParameters) {
        guard state == .idle else { return }
        
        state = .downloading
        _startDate = Date()
        
        // Perform simulated download on background thread using Task.sleep
        Task.detached { [weak self, delay, shouldSucceed, mockFileURL, identifier] in
            guard let self = self else { return }
            
            // Simulate download with periodic progress updates
            let chunks = 10
            let chunkDelay = delay / Double(chunks)
            let chunkDelayNanos = UInt64(chunkDelay * 1_000_000_000)
            
            for i in 1...chunks {
                // Check for cancellation
                let cancelled = await self.checkCancellation()
                if cancelled {
                    await self.handleCancellation()
                    return
                }
                
                // Sleep to simulate work using Task.sleep
                try? await Task.sleep(nanoseconds: chunkDelayNanos)
                
                // Update progress
                await self.updateProgress(chunk: i, totalChunks: chunks)
            }
            
            // Complete the download
            await self.completeDownload(success: shouldSucceed, fileURL: mockFileURL)
        }
    }
    
    func cancel() {
        isCancelled = true
        if state == .downloading {
            state = .cancelled
            _finishedDate = Date()
        }
    }
    
    func pause() {
        // No-op for mock
    }
    
    // MARK: - Internal Helpers
    
    private func checkCancellation() -> Bool {
        return isCancelled
    }
    
    private func handleCancellation() {
        state = .cancelled
        _finishedDate = Date()
        let error = NSError(domain: "MockDownloadable", code: -999, userInfo: [NSLocalizedDescriptionKey: "Download was cancelled"])
        onComplete?(.failure(error))
    }
    
    private func updateProgress(chunk: Int, totalChunks: Int) {
        let bytesTransferred = (_totalSize * Int64(chunk)) / Int64(totalChunks)
        _transferredBytes = bytesTransferred
        _progress?.completedUnitCount = bytesTransferred
        onProgress?(_transferredBytes, _totalSize)
    }
    
    private func completeDownload(success: Bool, fileURL: URL) {
        _finishedDate = Date()
        
        if success {
            state = .completed
            _transferredBytes = _totalSize
            _totalBytes = _totalSize
            _progress?.completedUnitCount = _totalSize
            onComplete?(.success(fileURL))
        } else {
            state = .failed
            let error = NSError(domain: "MockDownloadable", code: -1, userInfo: [NSLocalizedDescriptionKey: "Simulated download failure"])
            onComplete?(.failure(error))
        }
    }
    
    // MARK: - Test Helpers
    
    func getCurrentState() -> State {
        return state
    }
    
    func setOnComplete(_ callback: @escaping (Result<URL, Error>) -> Void) {
        self.onComplete = callback
    }
    
    func setOnProgress(_ callback: @escaping (Int64, Int64) -> Void) {
        self.onProgress = callback
    }
}

// MARK: - Mock Mirror Policy

/// Simple mirror policy that returns the mock downloadable
actor MockMirrorPolicy: MirrorPolicy {
    private var downloadables: [String: MockDownloadable] = [:]
    
    func setDownloadable(_ downloadable: MockDownloadable, for resourceId: String) {
        downloadables[resourceId] = downloadable
    }
    
    func downloadable(for resource: ResourceFile, lastDownloadableIdentifier: String?, error: Error?) -> Downloadable? {
        return downloadables[resource.id]
    }
}

// MARK: - Mock Download Processor

actor MockDownloadProcessor: DownloadProcessor {
    
    weak var observer: DownloadProcessorObserver?
    private(set) var isActive: Bool = true
    private var processingTasks: [String: Task<Void, Never>] = [:]
    
    func set(observer: DownloadProcessorObserver?) {
        self.observer = observer
    }
    
    func canProcess(downloadable: Downloadable) -> Bool {
        return downloadable is MockDownloadable
    }
    
    func process(_ downloadable: Downloadable) async {
        guard let mockDownloadable = downloadable as? MockDownloadable else {
            return
        }
        
        let identifier = await mockDownloadable.identifier
        
        // Notify observer that download began (nonisolated)
        if let observer = observer {
            Task {
                await observer.downloadDidBegin(self, downloadable: downloadable)
            }
        }
        
        // Create processing task
        let task = Task {
            // Set up completion callback
            await mockDownloadable.setOnComplete { @Sendable [weak self, weak downloadable] result in
                guard let self = self, let downloadable = downloadable else { return }
                
                Task {
                    switch result {
                    case .success(let url):
                        await self.observer?.downloadDidFinishTransfer(self, downloadable: downloadable, to: url)
                        await self.observer?.downloadDidFinish(self, downloadable: downloadable)
                    case .failure(let error):
                        await self.observer?.downloadDidError(self, downloadable: downloadable, error: error)
                    }
                    
                    // Clean up processing task
                    await self.removeProcessingTask(identifier: await downloadable.identifier)
                }
            }
            
            // Set up progress callback
            await mockDownloadable.setOnProgress { @Sendable [weak self, weak downloadable] transferred, total in
                guard let self = self, let downloadable = downloadable else { return }
                
                Task {
                    if transferred > 0 {
                        await self.observer?.downloadDidStartTransfer(self, downloadable: downloadable)
                    }
                    await self.observer?.downloadDidTransferData(self, downloadable: downloadable)
                }
            }
            
            // Start the download
            await mockDownloadable.start(with: [:])
        }
        
        processingTasks[identifier] = task
    }
    
    func enqueuePending() async {
        // No-op for mock processor
    }
    
    func pause() async {
        isActive = false
    }
    
    func resume() async {
        isActive = true
    }
    
    private func removeProcessingTask(identifier: String) {
        processingTasks[identifier] = nil
    }
}

// MARK: - Concurrency Tests

class DownloadQueueConcurrencyTests: XCTestCase, @unchecked Sendable {
    
    var downloadQueue: DownloadQueue!
    var processor: MockDownloadProcessor!
    var observer: DownloadQueueObserverMock!
    var tempDirectory: URL!
    
    override func setUpWithError() throws {
        // Create temporary directory for mock files
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadQueueConcurrencyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Create download queue with appropriate concurrency limit
        downloadQueue = DownloadQueue(simultaneousDownloads: 10)
        processor = MockDownloadProcessor()
        observer = DownloadQueueObserverMock()
        
        Task {
            await downloadQueue.add(processor: processor)
            await downloadQueue.set(observer: observer)
        }
    }
    
    override func tearDownWithError() throws {
        Task { [queue = downloadQueue!] in
            await queue.cancelAll()
        }
        
        downloadQueue = nil
        processor = nil
        observer = nil
        
        // Clean up temporary directory
        if let tempDirectory = tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
    }
    
    // MARK: - Test: Concurrent Enqueueing 500 Items
    
    func testConcurrentEnqueuing500Items() async throws {
        let itemCount = 500
        let concurrentTasks = 50
        let itemsPerTask = itemCount / concurrentTasks
        
        let successCounter = ActorCounter()
        let failureCounter = ActorCounter()
        let expectation = XCTestExpectation(description: "500 downloads should complete")
        expectation.expectedFulfillmentCount = itemCount
        
        // Create download tasks
        let downloadTasks = await createMockDownloadTasks(count: itemCount, delay: 0.01, shouldSucceed: true)
        
        // Set up observer callbacks
        await observer.setDidFinishCallback { @Sendable [successCounter, expectation] downloadTask, downloadable, location in
            Task {
                await successCounter.increment()
                expectation.fulfill()
            }
        }
        
        await observer.setDidFailCallback { @Sendable [failureCounter, expectation] downloadTask, error in
            Task {
                await failureCounter.increment()
                expectation.fulfill()
            }
        }
        
        // Launch concurrent tasks to enqueue downloads
        await withTaskGroup(of: Void.self) { group in
            for taskIndex in 0..<concurrentTasks {
                group.addTask {
                    let startIndex = taskIndex * itemsPerTask
                    let endIndex = min(startIndex + itemsPerTask, itemCount)
                    
                    for i in startIndex..<endIndex {
                        await self.downloadQueue.download(downloadTasks[i])
                    }
                }
            }
        }
        
        // Wait for completion
        await fulfillment(of: [expectation], timeout: 30.0)
        
        // Verify results
        let successCount = await successCounter.value
        let failureCount = await failureCounter.value
        
        XCTAssertEqual(successCount, itemCount, "All items should succeed")
        XCTAssertEqual(failureCount, 0, "No items should fail")
    }
    
    // MARK: - Test: Concurrent Enqueueing 1000 Items
    
    func testConcurrentEnqueuing1000Items() async throws {
        let itemCount = 1000
        let concurrentTasks = 100
        let itemsPerTask = itemCount / concurrentTasks
        
        let successCounter = ActorCounter()
        let failureCounter = ActorCounter()
        let expectation = XCTestExpectation(description: "1000 downloads should complete")
        expectation.expectedFulfillmentCount = itemCount
        
        // Create download tasks with shorter delays for faster test
        let downloadTasks = await createMockDownloadTasks(count: itemCount, delay: 0.005, shouldSucceed: true)
        
        // Set up observer callbacks
        await observer.setDidFinishCallback { @Sendable [successCounter, expectation] downloadTask, downloadable, location in
            Task {
                await successCounter.increment()
                expectation.fulfill()
            }
        }
        
        await observer.setDidFailCallback { @Sendable [failureCounter, expectation] downloadTask, error in
            Task {
                await failureCounter.increment()
                expectation.fulfill()
            }
        }
        
        // Launch concurrent tasks to enqueue downloads
        await withTaskGroup(of: Void.self) { group in
            for taskIndex in 0..<concurrentTasks {
                group.addTask {
                    let startIndex = taskIndex * itemsPerTask
                    let endIndex = min(startIndex + itemsPerTask, itemCount)
                    
                    for i in startIndex..<endIndex {
                        await self.downloadQueue.download(downloadTasks[i])
                    }
                }
            }
        }
        
        // Wait for completion with longer timeout for 1000 items
        await fulfillment(of: [expectation], timeout: 60.0)
        
        // Verify results
        let successCount = await successCounter.value
        let failureCount = await failureCounter.value
        
        XCTAssertEqual(successCount, itemCount, "All items should succeed")
        XCTAssertEqual(failureCount, 0, "No items should fail")
        
        // Verify queue is empty
        let queuedCount = await downloadQueue.queuedDownloadCount
        let currentCount = await downloadQueue.currentDownloadCount
        XCTAssertEqual(queuedCount, 0, "Queue should be empty")
        XCTAssertEqual(currentCount, 0, "No downloads should be in progress")
    }
    
    // MARK: - Test: Concurrent Enqueueing with Mixed Success/Failure
    
    func testConcurrentEnqueueingWithMixedSuccessFailure() async throws {
        let itemCount = 600
        let successRate = 0.7 // 70% success
        let expectedSuccesses = Int(Double(itemCount) * successRate)
        let expectedFailures = itemCount - expectedSuccesses
        
        let successCounter = ActorCounter()
        let failureCounter = ActorCounter()
        let expectation = XCTestExpectation(description: "All downloads should complete")
        expectation.expectedFulfillmentCount = itemCount
        
        // Create mixed download tasks
        let downloadTasks = await createMockDownloadTasksWithMixedResults(
            count: itemCount,
            successRate: successRate,
            delay: 0.01
        )
        
        // Set up observer callbacks
        await observer.setDidFinishCallback { @Sendable [successCounter, expectation] downloadTask, downloadable, location in
            Task {
                await successCounter.increment()
                expectation.fulfill()
            }
        }
        
        await observer.setDidFailCallback { @Sendable [failureCounter, expectation] downloadTask, error in
            Task {
                await failureCounter.increment()
                expectation.fulfill()
            }
        }
        
        // Launch concurrent tasks to enqueue downloads
        let concurrentTasks = 60
        let itemsPerTask = itemCount / concurrentTasks
        
        await withTaskGroup(of: Void.self) { group in
            for taskIndex in 0..<concurrentTasks {
                group.addTask {
                    let startIndex = taskIndex * itemsPerTask
                    let endIndex = min(startIndex + itemsPerTask, itemCount)
                    
                    for i in startIndex..<endIndex {
                        await self.downloadQueue.download(downloadTasks[i])
                    }
                }
            }
        }
        
        // Wait for completion
        await fulfillment(of: [expectation], timeout: 45.0)
        
        // Verify results
        let successCount = await successCounter.value
        let failureCount = await failureCounter.value
        
        XCTAssertEqual(successCount, expectedSuccesses, "Success count should match expected")
        XCTAssertEqual(failureCount, expectedFailures, "Failure count should match expected")
        XCTAssertEqual(successCount + failureCount, itemCount, "Total should equal item count")
    }
    
    // MARK: - Test: Concurrent Cancellation
    
    func testConcurrentCancellation() async throws {
        let itemCount = 500
        let itemsToCancel = 250
        
        let completedCounter = ActorCounter()
        let failedCounter = ActorCounter()
        let cancelledIds = ActorArray<String>()
        
        // Create download tasks with longer delays to allow cancellation
        let downloadTasks = await createMockDownloadTasks(count: itemCount, delay: 0.1, shouldSucceed: true)
        
        // Set up observer callbacks
        await observer.setDidFinishCallback { @Sendable [completedCounter] downloadTask, downloadable, location in
            Task {
                await completedCounter.increment()
            }
        }
        
        await observer.setDidFailCallback { @Sendable [failedCounter] downloadTask, error in
            Task {
                await failedCounter.increment()
            }
        }
        
        // Enqueue all downloads
        for task in downloadTasks {
            await downloadQueue.download(task)
        }
        
        // Wait a moment for downloads to start
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Launch concurrent cancellation tasks
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<itemsToCancel {
                group.addTask {
                    let taskId = downloadTasks[i].id
                    await cancelledIds.append(taskId)
                    await self.downloadQueue.cancel(with: taskId)
                }
            }
        }
        
        // Wait for remaining downloads to complete
        try await Task.sleep(nanoseconds: 8_000_000_000) // 8 seconds
        
        // Verify results
        let completed = await completedCounter.value
        let _ = await failedCounter.value
        let cancelled = await cancelledIds.count
        
        XCTAssertEqual(cancelled, itemsToCancel, "Should have attempted to cancel \(itemsToCancel) items")
        XCTAssertLessThan(completed, itemCount, "Not all items should complete due to cancellations")
        
        // Verify queue is clean
        let queuedCount = await downloadQueue.queuedDownloadCount
        XCTAssertEqual(queuedCount, 0, "Queue should be empty after cancellation")
    }
    
    // MARK: - Test: Concurrent Enqueueing and Cancellation
    
    func testConcurrentEnqueueingAndCancellation() async throws {
        let initialBatch = 300
        let additionalBatches = 3
        let batchSize = 100
        let itemsToCancel = 200
        
        let completedCounter = ActorCounter()
        let failedCounter = ActorCounter()
        let enqueuedCounter = ActorCounter()
        let cancelledCounter = ActorCounter()
        
        // Create initial batch
        let initialTasks = await createMockDownloadTasks(count: initialBatch, delay: 0.05, shouldSucceed: true)
        
        // Set up observer callbacks
        await observer.setDidFinishCallback { @Sendable [completedCounter] downloadTask, downloadable, location in
            Task {
                await completedCounter.increment()
            }
        }
        
        await observer.setDidFailCallback { @Sendable [failedCounter] downloadTask, error in
            Task {
                await failedCounter.increment()
            }
        }
        
        // Enqueue initial batch
        for task in initialTasks {
            await downloadQueue.download(task)
            await enqueuedCounter.increment()
        }
        
        // Launch concurrent tasks for enqueueing and cancellation
        await withTaskGroup(of: Void.self) { group in
            // Task 1: Continuously enqueue new items
            for batchIndex in 0..<additionalBatches {
                group.addTask {
                    let newTasks = await self.createMockDownloadTasks(
                        count: batchSize,
                        delay: 0.05,
                        shouldSucceed: true,
                        idPrefix: "batch-\(batchIndex)"
                    )
                    
                    for task in newTasks {
                        await self.downloadQueue.download(task)
                        await enqueuedCounter.increment()
                    }
                }
            }
            
            // Task 2: Randomly cancel items
            group.addTask {
                for i in 0..<itemsToCancel {
                    let taskId = initialTasks[i % initialBatch].id
                    await self.downloadQueue.cancel(with: taskId)
                    await cancelledCounter.increment()
                    
                    // Small delay between cancellations
                    try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
                }
            }
        }
        
        // Wait for all downloads to complete
        try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
        
        // Verify results
        let completed = await completedCounter.value
        let _ = await failedCounter.value
        let enqueued = await enqueuedCounter.value
        let cancelled = await cancelledCounter.value
        
        let totalExpected = initialBatch + (additionalBatches * batchSize)
        XCTAssertEqual(enqueued, totalExpected, "Should have enqueued all items")
        XCTAssertEqual(cancelled, itemsToCancel, "Should have cancelled requested items")
        XCTAssertGreaterThan(completed, 0, "Some downloads should complete")
        
        // Verify queue is empty
        let queuedCount = await downloadQueue.queuedDownloadCount
        let currentCount = await downloadQueue.currentDownloadCount
        XCTAssertEqual(queuedCount, 0, "Queue should be empty")
        XCTAssertEqual(currentCount, 0, "No downloads should be in progress")
    }
    
    // MARK: - Test: Concurrent Access to Queue State
    
    func testConcurrentAccessToQueueState() async throws {
        let itemCount = 200
        let queryIterations = 500
        let concurrentQueryTasks = 50
        
        // Create and enqueue downloads
        let downloadTasks = await createMockDownloadTasks(count: itemCount, delay: 0.02, shouldSucceed: true)
        
        for task in downloadTasks {
            await downloadQueue.download(task)
        }
        
        // Launch concurrent tasks that query queue state
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<concurrentQueryTasks {
                group.addTask {
                    for _ in 0..<(queryIterations / concurrentQueryTasks) {
                        // Randomly query different state methods
                        let queryType = Int.random(in: 0...4)
                        
                        switch queryType {
                        case 0:
                            let randomId = downloadTasks.randomElement()!.id
                            _ = await self.downloadQueue.hasDownload(for: randomId)
                        case 1:
                            let randomId = downloadTasks.randomElement()!.id
                            _ = await self.downloadQueue.download(for: randomId)
                        case 2:
                            let randomId = downloadTasks.randomElement()!.id
                            _ = await self.downloadQueue.isDownloading(for: randomId)
                        case 3:
                            _ = await self.downloadQueue.queuedDownloadCount
                        case 4:
                            _ = await self.downloadQueue.currentDownloadCount
                        default:
                            break
                        }
                        
                        // Yield to allow other tasks to run
                        await Task.yield()
                    }
                }
            }
            
            // Also add a task that enqueues new items
            group.addTask {
                let newTasks = await self.createMockDownloadTasks(count: 50, delay: 0.02, shouldSucceed: true, idPrefix: "additional")
                for task in newTasks {
                    await self.downloadQueue.download(task)
                    try? await Task.sleep(nanoseconds: 5_000_000) // 0.005 seconds
                }
            }
        }
        
        // Wait for downloads to complete
        try await Task.sleep(nanoseconds: 8_000_000_000) // 8 seconds
        
        // If we get here without crashes, the test passed
        XCTAssertTrue(true, "Concurrent state access completed without crashes")
    }
    
    // MARK: - Test: Stress Test with 1000 Items and Rapid Operations
    
    func testStressTestWith1000ItemsAndRapidOperations() async throws {
        let itemCount = 1000
        let cancellationCount = 300
        let queryCount = 1000
        
        let completedCounter = ActorCounter()
        
        // Create download tasks
        let downloadTasks = await createMockDownloadTasks(count: itemCount, delay: 0.01, shouldSucceed: true)
        
        // Set up observer
        await observer.setDidFinishCallback { @Sendable [completedCounter] downloadTask, downloadable, location in
            Task {
                await completedCounter.increment()
            }
        }
        
        // Launch all operations concurrently
        await withTaskGroup(of: Void.self) { group in
            // Task 1: Enqueue downloads
            group.addTask {
                for task in downloadTasks {
                    await self.downloadQueue.download(task)
                }
            }
            
            // Task 2: Random cancellations
            group.addTask {
                try? await Task.sleep(nanoseconds: 100_000_000) // Wait 0.1s before cancelling
                
                for _ in 0..<cancellationCount {
                    let randomTask = downloadTasks.randomElement()!
                    await self.downloadQueue.cancel(with: randomTask.id)
                }
            }
            
            // Task 3: Rapid state queries
            group.addTask {
                for _ in 0..<queryCount {
                    _ = await self.downloadQueue.queuedDownloadCount
                    _ = await self.downloadQueue.currentDownloadCount
                    
                    let randomTask = downloadTasks.randomElement()!
                    _ = await self.downloadQueue.hasDownload(for: randomTask.id)
                }
            }
        }
        
        // Wait for completion
        try await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
        
        // Verify system is stable
        let completed = await completedCounter.value
        XCTAssertGreaterThan(completed, 0, "Some downloads should complete")
        
        let queuedCount = await downloadQueue.queuedDownloadCount
        let currentCount = await downloadQueue.currentDownloadCount
        XCTAssertEqual(queuedCount, 0, "Queue should eventually be empty")
        XCTAssertEqual(currentCount, 0, "No downloads should be in progress")
    }
    
    // MARK: - Helper Methods
    
    private func createMockDownloadTasks(count: Int, delay: TimeInterval, shouldSucceed: Bool, idPrefix: String = "mock") async -> [DownloadTask] {
        var tasks: [DownloadTask] = []
        
        for i in 0..<count {
            let identifier = "\(idPrefix)-download-\(i)"
            let fileURL = tempDirectory.appendingPathComponent("\(identifier).tmp")
            
            // Create mock file
            try? "mock data".write(to: fileURL, atomically: true, encoding: .utf8)
            
            let mockDownloadable = MockDownloadable(
                identifier: identifier,
                delay: delay,
                shouldSucceed: shouldSucceed,
                fileURL: fileURL
            )
            
            let resource = Resource(
                id: identifier,
                main: FileMirror(id: identifier, location: "mock://\(identifier)", info: [:]),
                alternatives: [],
                fileURL: nil
            )
            
            let request = DownloadRequest(resource: resource, options: RequestOptions())
            let mirrorPolicy = MockMirrorPolicy()
            
            // Register the downloadable with the mirror policy
            await mirrorPolicy.setDownloadable(mockDownloadable, for: identifier)
            
            let downloadTask = DownloadTask(request: request, mirrorPolicy: mirrorPolicy)
            
            tasks.append(downloadTask)
        }
        
        return tasks
    }
    
    private func createMockDownloadTasksWithMixedResults(count: Int, successRate: Double, delay: TimeInterval) async -> [DownloadTask] {
        var tasks: [DownloadTask] = []
        
        for i in 0..<count {
            let shouldSucceed = Double.random(in: 0...1) <= successRate
            let identifier = "mixed-download-\(i)"
            let fileURL = tempDirectory.appendingPathComponent("\(identifier).tmp")
            
            // Create mock file
            try? "mock data".write(to: fileURL, atomically: true, encoding: .utf8)
            
            let mockDownloadable = MockDownloadable(
                identifier: identifier,
                delay: delay,
                shouldSucceed: shouldSucceed,
                fileURL: fileURL
            )
            
            let resource = Resource(
                id: identifier,
                main: FileMirror(id: identifier, location: "mock://\(identifier)", info: [:]),
                alternatives: [],
                fileURL: nil
            )
            
            let request = DownloadRequest(resource: resource, options: RequestOptions())
            let mirrorPolicy = MockMirrorPolicy()
            
            // Register the downloadable with the mirror policy
            await mirrorPolicy.setDownloadable(mockDownloadable, for: identifier)
            
            let downloadTask = DownloadTask(request: request, mirrorPolicy: mirrorPolicy)
            
            tasks.append(downloadTask)
        }
        
        return tasks
    }
    
    private func createTempFileURL(identifier: String) -> URL {
        return tempDirectory.appendingPathComponent("\(identifier).tmp")
    }
}
