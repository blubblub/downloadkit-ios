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

// MARK: - Concurrency Tests

class DownloadQueueConcurrencyTests: XCTestCase, @unchecked Sendable {
    
    var downloadQueue: DownloadQueue!
    var processor: MockDownloadProcessor!
    var observer: DownloadQueueObserverMock!
    var tempDirectory: URL!
        
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
        try await setUpWithError()
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
        try await setUpWithError()
        
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
        try await setUpWithError()
        
        let itemCount = 600
        let successRate = 0.7 // 70% success
        let expectedSuccesses = Int(Double(itemCount) * successRate)
        let expectedFailures = itemCount - expectedSuccesses
        
        let successCounter = ActorCounter()
        let failureCounter = ActorCounter()
        let expectation = XCTestExpectation(description: "All downloads should complete")
        expectation.expectedFulfillmentCount = itemCount
        
        // Create array of success values: first N items succeed, rest fail
        var successValues = [Bool]()
        successValues.append(contentsOf: Array(repeating: true, count: expectedSuccesses))
        successValues.append(contentsOf: Array(repeating: false, count: expectedFailures))
        
        // Create mixed download tasks
        let downloadTasks = await createMockDownloadTasksWithMixedResults(
            successValues: successValues,
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
        try await setUpWithError()
        
        let itemCount = 500
        let itemsToCancel = 250
        
        let completedCounter = ActorCounter()
        let failedCounter = ActorCounter()
        let cancelledIds = ActorArray<String>()
        
        // Create download tasks with longer delays to allow cancellation
        let downloadTasks = await createMockDownloadTasks(count: itemCount, delay: 3, shouldSucceed: true)
        
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
        let failed = await failedCounter.value
        let cancelled = await cancelledIds.count
        
        XCTAssertEqual(cancelled, itemsToCancel, "Should have attempted to cancel \(itemsToCancel) items")
        XCTAssertLessThan(completed, itemCount, "Not all items should complete due to cancellations")
        XCTAssertEqual(failed, itemsToCancel, "Cancelled items should be failed.")
        
        // Verify queue is clean
        let queuedCount = await downloadQueue.queuedDownloadCount
        XCTAssertEqual(queuedCount, 0, "Queue should be empty after cancellation")
    }
    
    // MARK: - Test: Concurrent Enqueueing and Cancellation
    
    func testConcurrentEnqueueingAndCancellation() async throws {
        try await setUpWithError()
        
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
        try await setUpWithError()
        
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
        try await setUpWithError()
        
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
    
    private func setUpWithError() async throws {
        // Create temporary directory for mock files
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadQueueConcurrencyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Create download queue with appropriate concurrency limit
        downloadQueue = DownloadQueue(simultaneousDownloads: 10)
        processor = MockDownloadProcessor()
        observer = DownloadQueueObserverMock()
        
        await downloadQueue.add(processor: processor)
        await downloadQueue.set(observer: observer)
    }
    
    private func createMockDownloadTasks(count: Int, delay: TimeInterval, shouldSucceed: Bool, idPrefix: String = "mock") async -> [DownloadTask] {
        var tasks: [DownloadTask] = []
        
        let mirrorPolicy = MockMirrorPolicy()
        
        for i in 0..<count {
            let identifier = "\(idPrefix)-download-\(i)"
            let fileURL = tempDirectory.appendingPathComponent("\(identifier).tmp")
            
            // Create mock file
            try? "mock data".write(to: fileURL, atomically: true, encoding: .utf8)
            
            let configuration = MockDownloadableConfiguration(finishedURL: fileURL, shouldSucceed: shouldSucceed, delay: delay)
            
            await mirrorPolicy.addConfiguration(configuration, forResource: identifier)
                        
            let resource = Resource(
                id: identifier,
                main: FileMirror(id: identifier, location: "mock://\(identifier)", info: [:]),
                alternatives: [],
                fileURL: nil
            )
            
            let request = DownloadRequest(resource: resource, options: RequestOptions())
            
            let downloadTask = DownloadTask(request: request, mirrorPolicy: mirrorPolicy)
            
            tasks.append(downloadTask)
        }
        
        return tasks
    }
    
    private func createMockDownloadTasksWithMixedResults(successValues: [Bool], delay: TimeInterval, idPrefix: String = "mixed") async -> [DownloadTask] {
        var tasks: [DownloadTask] = []
        
        let mirrorPolicy = MockMirrorPolicy()
        
        for (i, shouldSucceed) in successValues.enumerated() {
            let identifier = "\(idPrefix)-download-\(i)"
            let fileURL = tempDirectory.appendingPathComponent("\(identifier).tmp")
            
            // Create mock file
            try? "mock data".write(to: fileURL, atomically: true, encoding: .utf8)
            
            
            let configuration = MockDownloadableConfiguration(finishedURL: fileURL, shouldSucceed: shouldSucceed, delay: delay)
            
            await mirrorPolicy.addConfiguration(configuration, forResource: identifier)
                        
            let resource = Resource(
                id: identifier,
                main: FileMirror(id: identifier, location: "mock://\(identifier)", info: [:]),
                alternatives: [],
                fileURL: nil
            )
            
            let request = DownloadRequest(resource: resource, options: RequestOptions())
            
            let downloadTask = DownloadTask(request: request, mirrorPolicy: mirrorPolicy)
            
            tasks.append(downloadTask)
        }
        
        return tasks
    }
    
    private func createTempFileURL(identifier: String) -> URL {
        return tempDirectory.appendingPathComponent("\(identifier).tmp")
    }
}
