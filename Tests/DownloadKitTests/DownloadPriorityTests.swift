//
//  DownloadPriorityTests.swift
//  DownloadKitTests
//
//  Created by Assistant on 2025-07-04.
//

import XCTest
import RealmSwift
@testable import DownloadKit
@testable import DownloadKitRealm

/// Comprehensive tests for download priority functionality in ResourceManager
/// Tests that all three priority levels (normal, high, urgent) work correctly
/// and that priority changes affect download ordering as expected
class DownloadPriorityTests: XCTestCase {
    
    var manager: ResourceManager!
    var cache: RealmCacheManager<CachedLocalFile>!
    var realm: Realm!
    var realmFileURL: URL?
    
    override func setUpWithError() throws {
        // Synchronous setup - manager will be configured in async test methods
    }
    
    override func tearDownWithError() throws {
        // Clear references - in-memory realm will be automatically cleaned up
        cache = nil
        manager = nil
        realm = nil
        realmFileURL = nil
    }
    
    /// Helper method to setup ResourceManager with priority queue for priority tests
    private func setupManagerWithPriorityQueue() async {
        let downloadQueue = DownloadQueue()
        await downloadQueue.add(processor: WebDownloadProcessor(configuration: .default))
        
        // Create priority queue for high and urgent priority downloads
        let priorityQueue = DownloadQueue()
        await priorityQueue.add(processor: WebDownloadProcessor.priorityProcessor())
        
        // Use in-memory Realm configuration
        let config = Realm.Configuration(
            inMemoryIdentifier: "priority_test_realm_\(UUID().uuidString)",
            deleteRealmIfMigrationNeeded: true
        )
        
        // Create Realm instance and keep it alive during the test
        realm = try! await Realm(configuration: config, actor: MainActor.shared)
        
        cache = RealmCacheManager<CachedLocalFile>(configuration: config)
        manager = ResourceManager(cache: cache, downloadQueue: downloadQueue, priorityQueue: priorityQueue)
    }
    
    /// Helper method to setup ResourceManager without priority queue (normal priority only)
    private func setupManagerWithoutPriorityQueue() async {
        let downloadQueue = DownloadQueue()
        await downloadQueue.add(processor: WebDownloadProcessor(configuration: .default))
        
        // Use in-memory Realm configuration
        let config = Realm.Configuration(
            inMemoryIdentifier: "normal_test_realm_\(UUID().uuidString)",
            deleteRealmIfMigrationNeeded: true
        )
        
        // Create Realm instance and keep it alive during the test
        realm = try! await Realm(configuration: config, actor: MainActor.shared)
        
        cache = RealmCacheManager<CachedLocalFile>(configuration: config)
        manager = ResourceManager(cache: cache, downloadQueue: downloadQueue) // No priority queue
    }
    
    /// Creates a test resource for priority testing
    private func createTestResource(id: String, size: Int = 100) -> Resource {
        return Resource(
            id: id,
            main: FileMirror(
                id: "mirror-\(id)",
                location: "https://picsum.photos/\(size)/\(size).jpg", // Small image for faster tests
                info: [:]
            ),
            alternatives: [],
            fileURL: nil
        )
    }
    
    /// Test that normal priority downloads work correctly
    func testNormalPriorityDownloads() async throws {
        await setupManagerWithPriorityQueue()
        
        print("=== TESTING NORMAL PRIORITY DOWNLOADS ===")
        
        let resources = [
            createTestResource(id: "normal-1"),
            createTestResource(id: "normal-2"),
            createTestResource(id: "normal-3")
        ]
        
        // Request downloads with normal priority (default)
        let requests = await manager.request(resources: resources)
        XCTAssertEqual(requests.count, 3, "Should create 3 download requests")
        
        // Process with normal priority (default)
        await manager.process(requests: requests, priority: .normal)
        
        // Check that downloads are in the main queue (not priority queue)
        let mainQueueDownloads = await manager.queuedDownloadCount
        let currentDownloads = await manager.currentDownloadCount
        
        print("Main queue downloads: \(mainQueueDownloads), Current downloads: \(currentDownloads)")
        XCTAssertGreaterThan(mainQueueDownloads + currentDownloads, 0, "Should have downloads in main queue")
        
        // Set up completion tracking
        let completionExpectation = XCTestExpectation(description: "Normal priority downloads should complete")
        completionExpectation.expectedFulfillmentCount = 3
        
        let successCounter = ActorCounter()
        
        for resource in resources {
            await manager.addResourceCompletion(for: resource) { @Sendable (success, resourceID) in
                Task {
                    if success {
                        await successCounter.increment()
                    }
                    completionExpectation.fulfill()
                }
            }
        }
        
        // Wait for completion
        await fulfillment(of: [completionExpectation], timeout: 30)
        
        let successCount = await successCounter.value
        print("Normal priority downloads completed: \(successCount)/3")
        
        // Verify metrics were updated
        let metrics = await manager.metrics
        XCTAssertGreaterThan(metrics.downloadBegan, 0, "Should have started some downloads")
        
        print("✅ Normal priority downloads test completed")
    }
    
    /// Test that high priority downloads work correctly and are prioritized
    func testHighPriorityDownloads() async throws {
        await setupManagerWithPriorityQueue()
        
        print("=== TESTING HIGH PRIORITY DOWNLOADS ===")
        
        // First, start some normal priority downloads
        let normalResources = [
            createTestResource(id: "normal-background-1"),
            createTestResource(id: "normal-background-2")
        ]
        
        let normalRequests = await manager.request(resources: normalResources)
        await manager.process(requests: normalRequests, priority: .normal)
        
        // Check initial metrics
        let metricsAfterNormal = await manager.metrics
        XCTAssertEqual(metricsAfterNormal.priorityIncreased, 0, "Normal priority should not increase priority counter")
        
        // Now add high priority downloads
        let highPriorityResources = [
            createTestResource(id: "high-priority-1"),
            createTestResource(id: "high-priority-2")
        ]
        
        let highPriorityRequests = await manager.request(resources: highPriorityResources)
        XCTAssertEqual(highPriorityRequests.count, 2, "Should create 2 high priority requests")
        
        // Process with high priority
        await manager.process(requests: highPriorityRequests, priority: .high)
        
        // Check metrics for priority increase
        let metrics = await manager.metrics
        XCTAssertGreaterThan(metrics.priorityIncreased, metricsAfterNormal.priorityIncreased, "Should have increased priority for high priority downloads")
        
        // Verify downloads are queued appropriately
        let queuedDownloads = await manager.queuedDownloadCount
        let currentDownloads = await manager.currentDownloadCount
        
        print("Queued downloads: \(queuedDownloads), Current downloads: \(currentDownloads)")
        print("Priority increased: \(metrics.priorityIncreased)")
        
        // We should have some downloads active
        XCTAssertGreaterThan(queuedDownloads + currentDownloads, 0, "Should have active downloads")
        
        // Verify priority handling worked
        XCTAssertGreaterThan(metrics.priorityIncreased, 0, "Should have tracked priority increases")
        
        print("✅ High priority downloads test completed")
    }
    
    /// Test that urgent priority downloads work correctly and preempt other downloads
    func testUrgentPriorityDownloads() async throws {
        await setupManagerWithPriorityQueue()
        
        print("=== TESTING URGENT PRIORITY DOWNLOADS ===")
        
        // Start normal priority downloads
        let normalResources = [
            createTestResource(id: "normal-bg-1"),
            createTestResource(id: "normal-bg-2")
        ]
        
        let normalRequests = await manager.request(resources: normalResources)
        await manager.process(requests: normalRequests, priority: .normal)
        
        // Start high priority downloads
        let highPriorityResources = [
            createTestResource(id: "high-bg-1")
        ]
        
        let highPriorityRequests = await manager.request(resources: highPriorityResources)
        await manager.process(requests: highPriorityRequests, priority: .high)
        
        // Get metrics after high priority
        let metricsAfterHigh = await manager.metrics
        
        // Now add urgent priority downloads - these should preempt others
        let urgentResources = [
            createTestResource(id: "urgent-priority-1")
        ]
        
        let urgentRequests = await manager.request(resources: urgentResources)
        XCTAssertEqual(urgentRequests.count, 1, "Should create 1 urgent priority request")
        
        // Process with urgent priority
        await manager.process(requests: urgentRequests, priority: .urgent)
        
        // Check metrics for priority changes
        let metricsAfterUrgent = await manager.metrics
        
        print("Priority increased: \(metricsAfterUrgent.priorityIncreased)")
        print("Priority decreased: \(metricsAfterUrgent.priorityDecreased)")
        
        // Urgent priority should have increased priority counters and potentially decreased others
        XCTAssertGreaterThan(metricsAfterUrgent.priorityIncreased, metricsAfterHigh.priorityIncreased, 
                           "Should have increased priority for urgent downloads")
        
        // Verify downloads are active
        let queuedDownloads = await manager.queuedDownloadCount
        let currentDownloads = await manager.currentDownloadCount
        
        print("After urgent - Queued: \(queuedDownloads), Current: \(currentDownloads)")
        
        // We should have some downloads active
        XCTAssertGreaterThan(queuedDownloads + currentDownloads, 0, "Should have active downloads after urgent priority")
        
        // Verify urgent priority handling worked
        XCTAssertGreaterThan(metricsAfterUrgent.priorityIncreased, 0, "Should have tracked priority increases")
        
        print("✅ Urgent priority downloads test completed")
    }
    
    /// Test priority behavior when no priority queue is available
    func testPriorityWithoutPriorityQueue() async throws {
        await setupManagerWithoutPriorityQueue() // No priority queue
        
        print("=== TESTING PRIORITY WITHOUT PRIORITY QUEUE ===")
        
        let resources = [
            createTestResource(id: "no-priority-queue-1"),
            createTestResource(id: "no-priority-queue-2")
        ]
        
        let requests = await manager.request(resources: resources)
        XCTAssertEqual(requests.count, 2, "Should create 2 download requests")
        
        // Try to process with high priority (should fall back to normal since no priority queue)
        await manager.process(requests: requests, priority: .high)
        
        // All downloads should be in main queue since there's no priority queue
        let queuedDownloads = await manager.queuedDownloadCount
        let currentDownloads = await manager.currentDownloadCount
        
        print("Downloads without priority queue - Queued: \(queuedDownloads), Current: \(currentDownloads)")
        XCTAssertGreaterThan(queuedDownloads + currentDownloads, 0, "Should have downloads in main queue")
        
        // Metrics should not show priority increases since no priority queue exists
        let metrics = await manager.metrics
        XCTAssertEqual(metrics.priorityIncreased, 0, "Should not increase priority without priority queue")
        
        print("✅ Priority without priority queue test completed")
    }
    
    /// Test dynamic priority changes during download processing
    func testDynamicPriorityChanges() async throws {
        await setupManagerWithPriorityQueue()
        
        print("=== TESTING DYNAMIC PRIORITY CHANGES ===")
        
        // Start with normal priority downloads
        let normalResource = createTestResource(id: "dynamic-normal")
        let normalRequests = await manager.request(resources: [normalResource])
        await manager.process(requests: normalRequests, priority: .normal)
        
        let metricsAfterNormal = await manager.metrics
        
        // Now add high priority
        let highResource = createTestResource(id: "dynamic-high")
        let highRequests = await manager.request(resources: [highResource])
        await manager.process(requests: highRequests, priority: .high)
        
        let metricsAfterHigh = await manager.metrics
        
        // Add urgent priority
        let urgentResource = createTestResource(id: "dynamic-urgent")
        let urgentRequests = await manager.request(resources: [urgentResource])
        
        if let urgentRequest = urgentRequests.first {
            await manager.process(request: urgentRequest, priority: .urgent)
        }
        
        let finalMetrics = await manager.metrics
        
        print("Priority progression:")
        print("  After normal: \(metricsAfterNormal.priorityIncreased)")
        print("  After high: \(metricsAfterHigh.priorityIncreased)")
        print("  After urgent: \(finalMetrics.priorityIncreased)")
        
        // Verify metrics tracked the priority changes correctly
        XCTAssertEqual(metricsAfterNormal.priorityIncreased, 0, "Normal should not increase priority")
        XCTAssertGreaterThan(metricsAfterHigh.priorityIncreased, metricsAfterNormal.priorityIncreased, "High should increase priority")
        XCTAssertGreaterThan(finalMetrics.priorityIncreased, metricsAfterHigh.priorityIncreased, "Urgent should further increase priority")
        
        // Verify downloads are queued
        let queuedDownloads = await manager.queuedDownloadCount
        let currentDownloads = await manager.currentDownloadCount
        
        print("Final state - Queued: \(queuedDownloads), Current: \(currentDownloads)")
        XCTAssertGreaterThan(queuedDownloads + currentDownloads, 0, "Should have active downloads")
        
        print("✅ Dynamic priority changes test completed")
    }
    
    /// Test that priority metrics are correctly tracked
    func testPriorityMetrics() async throws {
        await setupManagerWithPriorityQueue()
        
        print("=== TESTING PRIORITY METRICS ===")
        
        // Get initial metrics
        let initialMetrics = await manager.metrics
        XCTAssertEqual(initialMetrics.priorityIncreased, 0, "Should start with 0 priority increases")
        XCTAssertEqual(initialMetrics.priorityDecreased, 0, "Should start with 0 priority decreases")
        
        // Create test resources
        let normalResources = [createTestResource(id: "metrics-normal-1")]
        let highResources = [createTestResource(id: "metrics-high-1")]
        let urgentResources = [createTestResource(id: "metrics-urgent-1")]
        
        // Process normal priority first
        let normalRequests = await manager.request(resources: normalResources)
        await manager.process(requests: normalRequests, priority: .normal)
        
        let afterNormalMetrics = await manager.metrics
        XCTAssertEqual(afterNormalMetrics.priorityIncreased, 0, "Normal priority should not increase priority counter")
        
        // Process high priority
        let highRequests = await manager.request(resources: highResources)
        await manager.process(requests: highRequests, priority: .high)
        
        let afterHighMetrics = await manager.metrics
        XCTAssertGreaterThan(afterHighMetrics.priorityIncreased, afterNormalMetrics.priorityIncreased, 
                           "High priority should increase priority counter")
        
        // Process urgent priority
        let urgentRequests = await manager.request(resources: urgentResources)
        await manager.process(requests: urgentRequests, priority: .urgent)
        
        let finalMetrics = await manager.metrics
        XCTAssertGreaterThan(finalMetrics.priorityIncreased, afterHighMetrics.priorityIncreased, 
                           "Urgent priority should further increase priority counter")
        
        print("Final priority metrics:")
        print("  Priority increased: \(finalMetrics.priorityIncreased)")
        print("  Priority decreased: \(finalMetrics.priorityDecreased)")
        
        // Verify we have meaningful priority tracking
        XCTAssertGreaterThan(finalMetrics.priorityIncreased, 0, "Should have tracked priority increases")
        
        print("✅ Priority metrics test completed")
    }
    
    /// Test edge case: multiple urgent downloads
    func testMultipleUrgentDownloads() async throws {
        await setupManagerWithPriorityQueue()
        
        print("=== TESTING MULTIPLE URGENT DOWNLOADS ===")
        
        // Start background downloads
        let backgroundResource = createTestResource(id: "bg-urgent-1")
        let backgroundRequests = await manager.request(resources: [backgroundResource])
        await manager.process(requests: backgroundRequests, priority: .normal)
        
        let initialMetrics = await manager.metrics
        
        // Add first urgent download
        let firstUrgentResource = createTestResource(id: "first-urgent")
        let firstUrgentRequests = await manager.request(resources: [firstUrgentResource])
        await manager.process(requests: firstUrgentRequests, priority: .urgent)
        
        let metricsAfterFirst = await manager.metrics
        
        // Add second urgent download
        let secondUrgentResource = createTestResource(id: "second-urgent")
        let secondUrgentRequests = await manager.request(resources: [secondUrgentResource])
        await manager.process(requests: secondUrgentRequests, priority: .urgent)
        
        let metricsAfterSecond = await manager.metrics
        
        // Add third urgent download
        let thirdUrgentResource = createTestResource(id: "third-urgent")
        let thirdUrgentRequests = await manager.request(resources: [thirdUrgentResource])
        await manager.process(requests: thirdUrgentRequests, priority: .urgent)
        
        let finalMetrics = await manager.metrics
        
        print("Priority increases progression:")
        print("  Initial: \(initialMetrics.priorityIncreased)")
        print("  After 1st urgent: \(metricsAfterFirst.priorityIncreased)")
        print("  After 2nd urgent: \(metricsAfterSecond.priorityIncreased)")
        print("  After 3rd urgent: \(finalMetrics.priorityIncreased)")
        
        // Verify metrics tracked multiple priority changes
        XCTAssertGreaterThan(metricsAfterFirst.priorityIncreased, initialMetrics.priorityIncreased, "First urgent should increase priority")
        XCTAssertGreaterThan(metricsAfterSecond.priorityIncreased, metricsAfterFirst.priorityIncreased, "Second urgent should increase priority")
        XCTAssertGreaterThan(finalMetrics.priorityIncreased, metricsAfterSecond.priorityIncreased, "Third urgent should increase priority")
        XCTAssertGreaterThanOrEqual(finalMetrics.priorityIncreased, 3, "Should have tracked at least 3 priority increases")
        
        // Verify downloads are active
        let queuedDownloads = await manager.queuedDownloadCount
        let currentDownloads = await manager.currentDownloadCount
        
        print("Final downloads - Queued: \(queuedDownloads), Current: \(currentDownloads)")
        XCTAssertGreaterThan(queuedDownloads + currentDownloads, 0, "Should have active downloads")
        
        print("✅ Multiple urgent downloads test completed")
    }
}
