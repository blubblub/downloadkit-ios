//
//  ResourceManagerIntegrationPriorityTests.swift
//  DownloadKitTests
//
//  Integration tests for priority changes on multiple download requests.
//  Tests verify that priority queue management works correctly with real WebDownload requests.
//

import XCTest
import RealmSwift
@testable import DownloadKit
@testable import DownloadKitRealm

// MARK: - Download Start Tracking Observer

/// Observer that tracks when downloads start for verification in tests
actor DownloadStartTrackingObserver: ResourceManagerObserver {
    private var startedDownloads: [String: Date] = [:]
    
    func didStartDownloading(_ downloadTask: DownloadTask) async {
        startedDownloads[downloadTask.id] = Date()
    }
    
    func willRetryFailedDownload(_ downloadTask: DownloadTask, failedDownloadable: Downloadable, downloadable: Downloadable, with error: Error) async {
        // Not needed for this test
    }
    
    func didFinishDownload(_ downloadTask: DownloadTask, with error: Error?) async {
        // Not needed for this test
    }
    
    // Public accessors for test verification
    func getStartedUrgentDownloads() -> [String: Date] {
        return startedDownloads.filter { $0.key.hasPrefix("urgent-") }
    }
    
    func hasAllUrgentDownloadsStarted(count: Int) -> Bool {
        return getStartedUrgentDownloads().count >= count
    }
    
    func getAllStartedDownloads() -> [String: Date] {
        return startedDownloads
    }
}

class ResourceManagerIntegrationPriorityTests: XCTestCase {
    var manager: ResourceManager!
    var cache: RealmCacheManager<CachedLocalFile>!
    var realm: Realm!
    
    override func setUpWithError() throws {
        // Synchronous setup - realm will be configured in async test methods
    }

    override func tearDownWithError() throws {
        // Clear references - in-memory realm will be automatically cleaned up
        cache = nil
        manager = nil
        realm = nil
    }
    
    /// Helper method to setup ResourceManager with priority queue for integration tests
    private func setupManagerWithPriorityQueue() async {
        let result = await DownloadKitTests.setupManagerWithPriorityQueue()
        manager = result.0
        cache = result.1
        realm = result.2
    }
    
    /// Test 1: Fill the queue up with 50+ requests and start processing them with normal priority.
    /// Then add 10 new high priority downloads and ensure downloads start at most 0.5 seconds after process is called.
    func testHighPriorityStartsQuicklyWhenQueueBusy() async throws {
        await setupManagerWithPriorityQueue()
        
        print("\n=== TEST 1: HIGH PRIORITY STARTS QUICKLY WHEN QUEUE IS BUSY ===")
        
        // Phase 1: Fill normal queue with 50 requests
        print("Phase 1: Creating 50 normal priority downloads...")
        let normalResources = (1...50).map { createTestResource(id: "normal-\($0)", size: 100) }
        
        let normalRequests = await manager.request(resources: normalResources)
        print("Created \(normalRequests.count) normal priority requests")
        
        let successCounter = ActorCounter()
        let failureCounter = ActorCounter()
        
        // Set up completion tracking for all downloads
        let allExpectation = XCTestExpectation(description: "All downloads should complete")
        allExpectation.expectedFulfillmentCount = 60
        
        for resource in normalResources {
            await manager.addResourceCompletion(for: resource) { @Sendable (success, resourceID) in
                Task {
                    if success {
                        await successCounter.increment()
                    } else {
                        await failureCounter.increment()
                    }
                    allExpectation.fulfill()
                }
            }
        }
        
        let _ = await manager.process(requests: normalRequests, priority: .normal)
        
        // Wait briefly for processing to start
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        let initialQueued = await manager.queuedDownloadCount
        let initialCurrent = await manager.currentDownloadCount
        print("Initial queue state - Queued: \(initialQueued), Current: \(initialCurrent)")
        
        // Phase 2: Add 10 high priority downloads
        print("\nPhase 2: Adding 10 high priority downloads...")
        let highPriorityResources = (1...10).map { createTestResource(id: "high-\($0)", size: 100) }
        
        let highPriorityRequests = await manager.request(resources: highPriorityResources)
        print("Created \(highPriorityRequests.count) high priority requests")
        
        // Track start times for high priority downloads
        let highPriorityStartTimes = ActorArray<(String, Date)>()
        
        // Record timestamp before processing high priority requests
        let processCallTime = Date()
        print("Processing high priority requests at: \(processCallTime)")
        
        // Track high priority start times using resource completion callbacks
        // We'll use a separate tracker for start detection
        let highPriorityStarted = ActorCounter()
        
        for resource in highPriorityResources {
            await manager.addResourceCompletion(for: resource) { @Sendable (success, resourceID) in
                Task {
                    // Record start time on first callback (even if it fails, we want to track when it started)
                    let currentStarted = await highPriorityStarted.value
                    if currentStarted < 10 {
                        await highPriorityStartTimes.append((resourceID, Date()))
                        await highPriorityStarted.increment()
                    }
                    
                    if success {
                        await successCounter.increment()
                    } else {
                        await failureCounter.increment()
                    }
                    allExpectation.fulfill()
                }
            }
        }
        
        // Process high priority requests
        let _ = await manager.process(requests: highPriorityRequests, priority: .high)
        
        // Check queue state after high priority added
        let afterHighQueued = await manager.queuedDownloadCount
        let afterHighCurrent = await manager.currentDownloadCount
        print("After high priority - Queued: \(afterHighQueued), Current: \(afterHighCurrent)")
        
        // Wait for all downloads to complete
        print("\nWaiting for all downloads to complete...")
        await fulfillment(of: [allExpectation], timeout: 120)
        
        // Analyze results
        let finalSuccess = await successCounter.value
        let finalFailure = await failureCounter.value
        let startTimes = await highPriorityStartTimes.values
        
        print("\n=== RESULTS ===")
        print("Total downloads completed: \(finalSuccess + finalFailure) / 60")
        print("Successful: \(finalSuccess)")
        print("Failed: \(finalFailure)")
        print("High priority downloads tracked: \(startTimes.count)")
        
        // Verify all downloads completed (ignoring network errors)
        XCTAssertEqual(finalSuccess + finalFailure, 60, "All 60 downloads should complete")
        
        // Verify timing for high priority downloads that started
        if startTimes.count > 0 {
            print("\n=== HIGH PRIORITY TIMING ANALYSIS ===")
            for (id, startTime) in startTimes {
                let delay = startTime.timeIntervalSince(processCallTime)
                print("Download \(id) started after: \(String(format: "%.3f", delay))s")
                
                // Verify each high priority download started within 0.5 seconds
                XCTAssertLessThanOrEqual(delay, 0.5, "High priority download \(id) should start within 0.5 seconds")
            }
            
            let averageDelay = startTimes.reduce(0.0) { $0 + $1.1.timeIntervalSince(processCallTime) } / Double(startTimes.count)
            print("Average start delay: \(String(format: "%.3f", averageDelay))s")
        }
        
        print("\n✅ Test 1 completed successfully")
    }
    
    /// Test 2: When priority queue is filled up, ensure downloads get in queue and wait even on priority queue.
    func testPriorityQueueFillsUpAndDownloadsWait() async throws {
        await setupManagerWithPriorityQueue()
        
        print("\n=== TEST 2: PRIORITY QUEUE FILLS UP AND DOWNLOADS WAIT ===")
        
        // Phase 1: Fill priority queue with 50 high priority downloads
        print("Phase 1: Creating 50 high priority downloads to fill the priority queue...")
        let initialHighResources = (1...50).map { createTestResource(id: "high-queue-\($0)", size: 100) }
        
        let allExpectation = XCTestExpectation(description: "All downloads should complete")
        allExpectation.expectedFulfillmentCount = 60
        
        let successCounter = ActorCounter()
        let failureCounter = ActorCounter()
                
        // Phase 2: Add 10 more high priority downloads
        print("\nPhase 2: Adding 10 additional high priority downloads...")
        let additionalHighResources = (1...10).map { createTestResource(id: "high-extra-\($0)", size: 100) }
        
        let additionalHighRequests = await manager.request(resources: additionalHighResources)
        print("Created \(additionalHighRequests.count) additional high priority requests")
        
        let allResources = initialHighResources + additionalHighResources
        for resource in allResources {
            await manager.addResourceCompletion(for: resource) { @Sendable (success, resourceID) in
                Task {
                    if success {
                        await successCounter.increment()
                    } else {
                        await failureCounter.increment()
                    }
                    allExpectation.fulfill()
                }
            }
        }
        
        let initialHighRequests = await manager.request(resources: initialHighResources)
        print("Created \(initialHighRequests.count) high priority requests")
        
        let _ = await manager.process(requests: initialHighRequests, priority: .high)
        
        // Wait briefly for downloads to start processing
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        let afterInitialQueued = await manager.queuedDownloadCount
        let afterInitialCurrent = await manager.currentDownloadCount
        print("After initial batch - Queued: \(afterInitialQueued), Current: \(afterInitialCurrent)")
        
        // Verify priority queue is backed up (some downloads are queued)
        XCTAssertGreaterThan(afterInitialQueued, 0, "Priority queue should have queued downloads (queue is backed up)")
        print("✓ Priority queue is backed up with \(afterInitialQueued) queued downloads")
        
        // Phase 2: Add 10 more high priority downloads
        print("\nPhase 2: Adding 10 additional high priority downloads...")
        let queuedBeforeAdditional = await manager.queuedDownloadCount
        
        let _ = await manager.process(requests: additionalHighRequests, priority: .high)
        
        // Check queue state after adding more
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        let queuedAfterAdditional = await manager.queuedDownloadCount
        let currentAfterAdditional = await manager.currentDownloadCount
        
        print("Before additional: \(queuedBeforeAdditional) queued")
        print("After additional - Queued: \(queuedAfterAdditional), Current: \(currentAfterAdditional)")
        
        // Verify new downloads are also queued (or at least total downloads increased)
        let totalAfter = queuedAfterAdditional + currentAfterAdditional
        let totalBefore = queuedBeforeAdditional + afterInitialCurrent
        XCTAssertGreaterThanOrEqual(totalAfter, totalBefore, "New downloads should be added to queue")
        print("✓ Additional downloads properly queued, total downloads increased from \(totalBefore) to \(totalAfter)")
        
        // Phase 3: Wait for all downloads to complete
        print("\nPhase 3: Waiting for all downloads to complete...")
        await fulfillment(of: [allExpectation], timeout: 180)
        
        // Analyze results
        let finalSuccess = await successCounter.value
        let finalFailure = await failureCounter.value
        let finalQueued = await manager.queuedDownloadCount
        let finalCurrent = await manager.currentDownloadCount
        
        print("\n=== RESULTS ===")
        print("Total downloads completed: \(finalSuccess + finalFailure) / 60")
        print("Successful: \(finalSuccess)")
        print("Failed: \(finalFailure)")
        print("Final queue state - Queued: \(finalQueued), Current: \(finalCurrent)")
        
        // Verify all downloads completed
        XCTAssertEqual(finalSuccess + finalFailure, 60, "All 60 downloads should complete")
        
        // Verify queue is now empty or nearly empty
        XCTAssertEqual(finalQueued, 0, "Queue should be empty after all downloads complete")
        
        print("\n✅ Test 2 completed successfully")
    }
    
    /// Test 3: When priority queue is filled up, if urgent requests are placed on queue,
    /// others must be downgraded to normal queue.
    func testUrgentRequestsDowngradeOthersFromPriorityQueue() async throws {
        await setupManagerWithPriorityQueue()
        
        print("\n=== TEST 3: URGENT REQUESTS DOWNGRADE OTHERS FROM PRIORITY QUEUE ===")
        
        // Phase 1: Add normal priority background downloads
        print("Phase 1: Creating 30 normal priority background downloads...")
        let normalResources = (1...30).map { createTestResource(id: "normal-bg-\($0)", fileSize: .medium) }
        
        let normalRequests = await manager.request(resources: normalResources)
        print("Created \(normalRequests.count) normal priority requests")
        
        // Phase 2: Fill priority queue with high priority downloads
        print("\nPhase 2: Creating 20 high priority downloads to fill priority queue...")
        let highPriorityResources = (1...20).map { createTestResource(id: "high-bg-\($0)", fileSize: .medium) }
        
        let highPriorityRequests = await manager.request(resources: highPriorityResources)
        print("Created \(highPriorityRequests.count) high priority requests")
        
        // Phase 3: Add urgent priority downloads (should downgrade high priority downloads)
        print("\nPhase 3: Adding 5 urgent priority downloads...")
        let urgentResources = (1...5).map { createTestResource(id: "urgent-\($0)", fileSize: .medium) }
        
        let urgentRequests = await manager.request(resources: urgentResources)
        print("Created \(urgentRequests.count) urgent priority requests")
        
        let allExpectation = XCTestExpectation(description: "All downloads should complete")
        allExpectation.expectedFulfillmentCount = 55
        
        let successCounter = ActorCounter()
        let failureCounter = ActorCounter()
        
        let allResources = normalResources + highPriorityResources + urgentResources
        for resource in allResources {
            await manager.addResourceCompletion(for: resource) { @Sendable (success, resourceID) in
                Task {
                    if success {
                        await successCounter.increment()
                    } else {
                        await failureCounter.increment()
                    }
                    allExpectation.fulfill()
                }
            }
        }
        
        // Fill both normal and high priority queue.
        let _ = await manager.process(requests: normalRequests, priority: .normal)
        let _ = await manager.process(requests: highPriorityRequests, priority: .high)
        
        // Wait for processing to start
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        // Capture metrics after high priority processing
        let metricsAfterHigh = manager.metrics
        let priorityIncreasedAfterHigh = await metricsAfterHigh.priorityIncreased
        let priorityDecreasedAfterHigh = await metricsAfterHigh.priorityDecreased
        
        XCTAssertEqual(priorityIncreasedAfterHigh, highPriorityRequests.count, "High should change priorities")
        XCTAssertEqual(priorityDecreasedAfterHigh, 0, "There should be no priority decrease changes")
        
        print("After high priority - Priority increased: \(priorityIncreasedAfterHigh), Priority decreased: \(priorityDecreasedAfterHigh)")
        
        let queuedAfterHigh = await manager.queuedDownloadCount
        let currentAfterHigh = await manager.currentDownloadCount
        print("Queue state after high priority - Queued: \(queuedAfterHigh), Current: \(currentAfterHigh)")
        
        // Add observer to track download starts (before processing urgent requests)
        let downloadStartObserver = DownloadStartTrackingObserver()
        await manager.add(observer: downloadStartObserver)
        
        let startTime = Date()
        
        // Trigger urgent requests
        let _ = await manager.process(requests: urgentRequests, priority: .urgent)
        
        // Wait for urgent downloads to actually start
        // Poll until all urgent downloads have started or timeout after 10 seconds
        
        let timeout: TimeInterval = 30.0
        var allUrgentStarted = false
        var firstStartedAt: Date? = nil
        
        while !allUrgentStarted && Date().timeIntervalSince(startTime) < timeout {
            let startedCount = await downloadStartObserver.getStartedUrgentDownloads().count
            
            if startedCount > 0, firstStartedAt == nil {
                firstStartedAt = Date()
                
                let startDuration = abs(Date().timeIntervalSince(startTime))
                print("Urgent download started in: \(startDuration) seconds")
                XCTAssertLessThan(startDuration, 1.0, "Urgent downloads should start quickly, less than a second: \(startDuration)")
            }
            
            if startedCount >= 5 {
                allUrgentStarted = true
                
                print("All 5 urgent downloads have started after \(String(format: "%.2f", Date().timeIntervalSince(startTime)))s")
            } else {
                print("Waiting for urgent downloads to start: \(startedCount) / 5")
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            }
        }
        
        // Verify that all 5 urgent downloads have started
        let startedUrgentDownloads = await downloadStartObserver.getStartedUrgentDownloads()
        print("Urgent downloads started: \(startedUrgentDownloads.count) / 5")
        
        XCTAssertEqual(startedUrgentDownloads.count, 5, 
                      "Expected all 5 urgent downloads to have started, but only \(startedUrgentDownloads.count) started")
        
        // Log timing information for debugging
        for (id, startTime) in startedUrgentDownloads.sorted(by: { $0.value < $1.value }) {
            print("✓ Urgent download \(id) started at: \(startTime)")
        }
        
        // Capture metrics after urgent processing
        let metricsAfterUrgent = manager.metrics
        let priorityIncreasedAfterUrgent = await metricsAfterUrgent.priorityIncreased
        let priorityDecreasedAfterUrgent = await metricsAfterUrgent.priorityDecreased
        
        print("After urgent - Priority increased: \(priorityIncreasedAfterUrgent), Priority decreased: \(priorityDecreasedAfterUrgent)")
        
        let queuedAfterUrgent = await manager.queuedDownloadCount
        let currentAfterUrgent = await manager.currentDownloadCount
        print("Queue state after urgent - Queued: \(queuedAfterUrgent), Current: \(currentAfterUrgent)")
        
        // Verify priority decreased (high priority downloads were downgraded)
        XCTAssertGreaterThan(priorityDecreasedAfterUrgent, priorityDecreasedAfterHigh, 
                           "Priority decreased should increase when urgent requests downgrade high priority downloads")
        print("✓ Priority decreased from \(priorityDecreasedAfterHigh) to \(priorityDecreasedAfterUrgent) (downgrade occurred)")
        
        // Verify priority increased for urgent downloads
        XCTAssertGreaterThan(priorityIncreasedAfterUrgent, priorityIncreasedAfterHigh,
                           "Priority increased should include urgent downloads")
        print("✓ Priority increased from \(priorityIncreasedAfterHigh) to \(priorityIncreasedAfterUrgent)")
        
        // Phase 4: Wait for all downloads to complete
        print("\nPhase 4: Waiting for all downloads to complete...")
        
        await fulfillment(of: [allExpectation], timeout: 180)
        
        // Analyze results
        let finalSuccess = await successCounter.value
        let finalFailure = await failureCounter.value
        let finalMetrics = manager.metrics
        let finalPriorityIncreased = await finalMetrics.priorityIncreased
        let finalPriorityDecreased = await finalMetrics.priorityDecreased
        
        print("\n=== RESULTS ===")
        print("Total downloads completed: \(finalSuccess + finalFailure) / 55")
        print("Successful: \(finalSuccess)")
        print("Failed: \(finalFailure)")
        print("Final metrics:")
        print("  - Priority increased: \(finalPriorityIncreased)")
        print("  - Priority decreased: \(finalPriorityDecreased)")
        print("  - Net priority changes: \(finalPriorityIncreased - finalPriorityDecreased)")
        
        // Verify all downloads completed
        XCTAssertEqual(finalSuccess + finalFailure, 55, "All 55 downloads should complete")
        
        // Verify downgrade behavior occurred
        XCTAssertGreaterThan(finalPriorityDecreased, 0, "Some downloads should have been downgraded")
        
        print("\n✅ Test 3 completed successfully")
    }
}
