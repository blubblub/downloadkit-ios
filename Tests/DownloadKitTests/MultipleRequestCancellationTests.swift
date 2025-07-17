import XCTest
import RealmSwift
@testable import DownloadKit
@testable import DownloadKitRealm

class MultipleRequestCancellationTests: XCTestCase {
    
    var manager: ResourceManager!
    var cache: RealmCacheManager<CachedLocalFile>!
    var realm: Realm!
    
    override func setUpWithError() throws {
        // Synchronous setup - manager will be configured in async test methods
    }
    
    func setupManager() async {
        let downloadQueue = DownloadQueue()
        await downloadQueue.add(processor: WebDownloadProcessor(configuration: .default))
        
        // Use in-memory configuration to avoid cache conflicts
        let config = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
        
        // Create Realm instance and keep it alive during the test
        realm = try! await Realm(configuration: config, actor: MainActor.shared)
        
        cache = RealmCacheManager<CachedLocalFile>(configuration: config)
        manager = ResourceManager(cache: cache, downloadQueue: downloadQueue)
    }
    
    func setupWithPriorityQueue() async {
        let downloadQueue = DownloadQueue()
        await downloadQueue.add(processor: WebDownloadProcessor(configuration: .default))
        
        let priorityQueue = DownloadQueue()
        await priorityQueue.add(processor: WebDownloadProcessor.priorityProcessor())
        
        // Use in-memory configuration to avoid cache conflicts
        let config = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
        
        // Create Realm instance and keep it alive during the test
        realm = try! await Realm(configuration: config, actor: MainActor.shared)
        
        cache = RealmCacheManager<CachedLocalFile>(configuration: config)
        manager = ResourceManager(cache: cache, downloadQueue: downloadQueue, priorityQueue: priorityQueue)
    }

    override func tearDownWithError() throws {
        // Clear references - in-memory realm will be automatically cleaned up
        cache = nil
        manager = nil
        realm = nil
    }
    
    // MARK: - Empty Array Tests
    
    func testCancelEmptyArray() async {
        await setupManager()
        
        // Test that cancelling empty array doesn't crash or cause issues
        await manager.cancel(requests: [])
        
        // Verify manager state is unaffected
        let currentDownloadCount = await manager.currentDownloadCount
        XCTAssertEqual(currentDownloadCount, 0, "Manager should remain empty after cancelling empty array")
        
        let queuedDownloadCount = await manager.queuedDownloadCount
        XCTAssertEqual(queuedDownloadCount, 0, "Manager should remain empty after cancelling empty array")
        
        let isActive = await manager.isActive
        XCTAssertTrue(isActive, "Manager should remain active after cancelling empty array")
    }
    
    // MARK: - Single Request Array Tests
    
    func testCancelSingleRequestArray() async {
        await setupManager()
        
        let resource = Resource(id: "single-cancel-test", 
                               main: FileMirror(id: "single-cancel-test",
                                              location: "https://example.com/fakefile.jpg",
                                              info: [:]),
                               alternatives: [], 
                               fileURL: nil)
        
        let request = await manager.request(resource: resource)
        XCTAssertNotNil(request, "Request should be created")
        
        let expectation = self.expectation(description: "Single request cancellation should trigger completion")
        
        await manager.addResourceCompletion(for: resource) { (success: Bool, resourceId: String) in
            XCTAssertFalse(success, "Cancellation should trigger completion with success: false")
            XCTAssertEqual(resourceId, "single-cancel-test", "Resource ID should match")
            expectation.fulfill()
        }
        
        // Cancel using array method with single request
        await manager.cancel(requests: [request!])
        
        await fulfillment(of: [expectation], timeout: 2)
        
        // Verify state cleanup
        let downloadableIdentifier = await request!.downloadableIdentifier()
        let isDownloading = await manager.isDownloading(for: downloadableIdentifier)
        XCTAssertFalse(isDownloading, "Download should no longer be in progress after cancellation")
        
        let hasDownloadable = await manager.hasDownloadable(with: downloadableIdentifier)
        XCTAssertFalse(hasDownloadable, "Download should be removed from queue after cancellation")
    }
    
    // MARK: - Multiple Request Array Tests
    
    func testCancelMultipleRequestsArray() async {
        await setupManager()
        
        let resources = [
            Resource(id: "multi-cancel-test-1", 
                    main: FileMirror(id: "multi-cancel-test-1",
                                   location: "https://example.com/fakefile1.jpg",
                                   info: [:]),
                    alternatives: [], 
                    fileURL: nil),
            Resource(id: "multi-cancel-test-2", 
                    main: FileMirror(id: "multi-cancel-test-2",
                                   location: "https://example.com/fakefile2.jpg",
                                   info: [:]),
                    alternatives: [], 
                    fileURL: nil),
            Resource(id: "multi-cancel-test-3", 
                    main: FileMirror(id: "multi-cancel-test-3",
                                   location: "https://example.com/fakefile3.jpg",
                                   info: [:]),
                    alternatives: [], 
                    fileURL: nil)
        ]
        
        let requests = await manager.request(resources: resources)
        XCTAssertEqual(requests.count, 3, "Should have 3 requests")
        
        let expectation = self.expectation(description: "All requests should be cancelled")
        expectation.expectedFulfillmentCount = 3
        
        // Add completion handlers for all resources
        for resource in resources {
            await manager.addResourceCompletion(for: resource) { (success: Bool, resourceId: String) in
                XCTAssertFalse(success, "Cancellation should trigger completion with success: false")
                XCTAssertTrue(["multi-cancel-test-1", "multi-cancel-test-2", "multi-cancel-test-3"].contains(resourceId), 
                            "Resource ID should be one of the test resources")
                expectation.fulfill()
            }
        }
        
        // Cancel all requests using array method
        await manager.cancel(requests: requests)
        
        await fulfillment(of: [expectation], timeout: 2)
        
        // Verify all requests are cleaned up
        for request in requests {
            let downloadableIdentifier = await request.downloadableIdentifier()
            let isDownloading = await manager.isDownloading(for: downloadableIdentifier)
            XCTAssertFalse(isDownloading, "Download should no longer be in progress after cancellation")
            
            let hasDownloadable = await manager.hasDownloadable(with: downloadableIdentifier)
            XCTAssertFalse(hasDownloadable, "Download should be removed from queue after cancellation")
        }
    }
    
    // MARK: - Callback Triggering Tests
    
    func testCancelMultipleRequestsTriggersAllCallbacks() async {
        await setupManager()
        
        let resources = [
            Resource(id: "callback-test-1", 
                    main: FileMirror(id: "callback-test-1",
                                   location: "https://example.com/fakefile1.jpg",
                                   info: [:]),
                    alternatives: [], 
                    fileURL: nil),
            Resource(id: "callback-test-2", 
                    main: FileMirror(id: "callback-test-2",
                                   location: "https://example.com/fakefile2.jpg",
                                   info: [:]),
                    alternatives: [], 
                    fileURL: nil)
        ]
        
        let requests = await manager.request(resources: resources)
        XCTAssertEqual(requests.count, 2, "Should have 2 requests")
        
        // Use thread-safe counter to track callback calls
        let callbackCounter = ActorCounter()
        let callbackIds = ActorArray<String>()
        
        let expectation = self.expectation(description: "All callbacks should be triggered")
        expectation.expectedFulfillmentCount = 4 // 2 callbacks per resource = 4 total
        
        // Add multiple completion handlers for each resource
        for resource in resources {
            await manager.addResourceCompletion(for: resource) { (success: Bool, resourceId: String) in
                XCTAssertFalse(success, "Cancellation should trigger completion with success: false")
                Task {
                    await callbackCounter.increment()
                    await callbackIds.append(resourceId)
                }
                expectation.fulfill()
            }
            
            await manager.addResourceCompletion(for: resource) { (success: Bool, resourceId: String) in
                XCTAssertFalse(success, "Cancellation should trigger completion with success: false")
                Task {
                    await callbackCounter.increment()
                    await callbackIds.append(resourceId)
                }
                expectation.fulfill()
            }
        }
        
        // Cancel all requests
        await manager.cancel(requests: requests)
        
        await fulfillment(of: [expectation], timeout: 2)
        
        // Verify all callbacks were called
        let finalCount = await callbackCounter.value
        XCTAssertEqual(finalCount, 4, "All 4 callbacks should have been called")
        
        let finalIds = await callbackIds.values
        XCTAssertEqual(finalIds.count, 4, "Should have 4 callback IDs")
        
        // Verify both resources had their callbacks triggered
        let uniqueIds = Set(finalIds)
        XCTAssertTrue(uniqueIds.contains("callback-test-1"), "First resource callbacks should be triggered")
        XCTAssertTrue(uniqueIds.contains("callback-test-2"), "Second resource callbacks should be triggered")
    }
    
    // MARK: - State Management Tests
    
    func testCancelMultipleRequestsStateManagement() async {
        await setupManager()
        
        let resources = [
            Resource(id: "state-test-1", 
                    main: FileMirror(id: "state-test-1",
                                   location: "https://example.com/fakefile1.jpg",
                                   info: [:]),
                    alternatives: [], 
                    fileURL: nil),
            Resource(id: "state-test-2", 
                    main: FileMirror(id: "state-test-2",
                                   location: "https://example.com/fakefile2.jpg",
                                   info: [:]),
                    alternatives: [], 
                    fileURL: nil),
            Resource(id: "state-test-3", 
                    main: FileMirror(id: "state-test-3",
                                   location: "https://example.com/fakefile3.jpg",
                                   info: [:]),
                    alternatives: [], 
                    fileURL: nil)
        ]
        
        let requests = await manager.request(resources: resources)
        XCTAssertEqual(requests.count, 3, "Should have 3 requests")
        
        // Cancel all requests
        await manager.cancel(requests: requests)
        
        // Verify manager state is cleaned up
        let currentDownloadCount = await manager.currentDownloadCount
        XCTAssertEqual(currentDownloadCount, 0, "No downloads should be current after cancellation")
        
        let queuedDownloadCount = await manager.queuedDownloadCount
        XCTAssertEqual(queuedDownloadCount, 0, "No downloads should be queued after cancellation")
        
        let totalDownloads = await manager.downloads.count
        XCTAssertEqual(totalDownloads, 0, "No downloads should exist after cancellation")
        
        // Verify individual request states
        for request in requests {
            let downloadableIdentifier = await request.downloadableIdentifier()
            let isDownloading = await manager.isDownloading(for: downloadableIdentifier)
            XCTAssertFalse(isDownloading, "Individual request should not be downloading after cancellation")
            
            let hasDownloadable = await manager.hasDownloadable(with: downloadableIdentifier)
            XCTAssertFalse(hasDownloadable, "Individual request should not have downloadable after cancellation")
        }
    }
    
    // MARK: - Progress Tracking Tests
    
    func testCancelMultipleRequestsProgressTracking() async {
        await setupManager()
        
        let resources = [
            Resource(id: "progress-test-1", 
                    main: FileMirror(id: "progress-test-1",
                                   location: "https://example.com/fakefile1.jpg",
                                   info: [:]),
                    alternatives: [], 
                    fileURL: nil),
            Resource(id: "progress-test-2", 
                    main: FileMirror(id: "progress-test-2",
                                   location: "https://example.com/fakefile2.jpg",
                                   info: [:]),
                    alternatives: [], 
                    fileURL: nil)
        ]
        
        let requests = await manager.request(resources: resources)
        XCTAssertEqual(requests.count, 2, "Should have 2 requests")
        
        let expectation = self.expectation(description: "Progress tracking should be cleaned up")
        expectation.expectedFulfillmentCount = 2
        
        // Add completion handlers to track when cancellation completes
        for resource in resources {
            await manager.addResourceCompletion(for: resource) { (success: Bool, resourceId: String) in
                XCTAssertFalse(success, "Cancellation should trigger completion with success: false")
                expectation.fulfill()
            }
        }
        
        // Cancel all requests
        await manager.cancel(requests: requests)
        
        await fulfillment(of: [expectation], timeout: 2)
        
        // Verify progress tracking is cleaned up for all requests
        for request in requests {
            let downloadableIdentifier = await request.downloadableIdentifier()
            let progressAfter = await manager.progress.progresses[downloadableIdentifier]
            XCTAssertNil(progressAfter, "Progress should be cleaned up after cancellation for \(downloadableIdentifier)")
        }
    }
    
    // MARK: - Priority Queue Tests
    
    func testCancelMultipleRequestsWithPriorityQueue() async {
        await setupWithPriorityQueue()
        
        let resources = [
            Resource(id: "priority-cancel-test-1", 
                    main: FileMirror(id: "priority-cancel-test-1",
                                   location: "https://example.com/fakefile1.jpg",
                                   info: [:]),
                    alternatives: [], 
                    fileURL: nil),
            Resource(id: "priority-cancel-test-2", 
                    main: FileMirror(id: "priority-cancel-test-2",
                                   location: "https://example.com/fakefile2.jpg",
                                   info: [:]),
                    alternatives: [], 
                    fileURL: nil)
        ]
        
        let requests = await manager.request(resources: resources)
        XCTAssertEqual(requests.count, 2, "Should have 2 requests")
        
        let expectation = self.expectation(description: "Priority queue cancellation should work")
        expectation.expectedFulfillmentCount = 2
        
        // Add completion handlers
        for resource in resources {
            await manager.addResourceCompletion(for: resource) { (success: Bool, resourceId: String) in
                XCTAssertFalse(success, "Cancellation should trigger completion with success: false")
                expectation.fulfill()
            }
        }
        
        // Cancel all requests
        await manager.cancel(requests: requests)
        
        await fulfillment(of: [expectation], timeout: 2)
        
        // Verify requests are cleaned up from both normal and priority queues
        for request in requests {
            let downloadableIdentifier = await request.downloadableIdentifier()
            let isDownloading = await manager.isDownloading(for: downloadableIdentifier)
            XCTAssertFalse(isDownloading, "Download should not be in progress after cancellation")
            
            let hasDownloadable = await manager.hasDownloadable(with: downloadableIdentifier)
            XCTAssertFalse(hasDownloadable, "Download should be removed from both queues after cancellation")
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testCancelRequestArrayWithMixedValidInvalidRequests() async {
        await setupManager()
        
        let validResource = Resource(id: "valid-mixed-test", 
                                   main: FileMirror(id: "valid-mixed-test",
                                                  location: "https://example.com/fakefile.jpg",
                                                  info: [:]),
                                   alternatives: [], 
                                   fileURL: nil)
        
        let validRequest = await manager.request(resource: validResource)
        XCTAssertNotNil(validRequest, "Valid request should be created")
        
        // Create a request for a resource that doesn't exist in the cache
        let invalidResource = Resource(id: "invalid-mixed-test", 
                                     main: FileMirror(id: "invalid-mixed-test",
                                                    location: "https://example.com/fakefile.jpg",
                                                    info: [:]),
                                     alternatives: [], 
                                     fileURL: nil)
        
        let invalidRequest = await manager.request(resource: invalidResource)
        XCTAssertNotNil(invalidRequest, "Invalid request should still be created")
        
        let expectation = self.expectation(description: "Mixed request cancellation should handle all requests")
        expectation.expectedFulfillmentCount = 2
        
        // Add completion handlers for both resources
        await manager.addResourceCompletion(for: validResource) { (success: Bool, resourceId: String) in
            XCTAssertFalse(success, "Valid request cancellation should trigger completion with success: false")
            expectation.fulfill()
        }
        
        await manager.addResourceCompletion(for: invalidResource) { (success: Bool, resourceId: String) in
            XCTAssertFalse(success, "Invalid request cancellation should trigger completion with success: false")
            expectation.fulfill()
        }
        
        // Cancel both requests together
        await manager.cancel(requests: [validRequest!, invalidRequest!])
        
        await fulfillment(of: [expectation], timeout: 2)
    }
    
    // MARK: - Large Array Tests
    
    func testCancelLargeArrayOfRequests() async {
        await setupManager()
        
        // Create a large number of resources
        let resources = (1...50).map { index in
            Resource(id: "large-array-test-\(index)", 
                    main: FileMirror(id: "large-array-test-\(index)",
                                   location: "https://example.com/fakefile\(index).jpg",
                                   info: [:]),
                    alternatives: [], 
                    fileURL: nil)
        }
        
        let requests = await manager.request(resources: resources)
        XCTAssertEqual(requests.count, 50, "Should have 50 requests")
        
        let expectation = self.expectation(description: "Large array cancellation should work")
        expectation.expectedFulfillmentCount = 50
        
        // Add completion handlers for all resources
        for resource in resources {
            await manager.addResourceCompletion(for: resource) { (success: Bool, resourceId: String) in
                XCTAssertFalse(success, "Cancellation should trigger completion with success: false")
                XCTAssertTrue(resourceId.hasPrefix("large-array-test-"), "Resource ID should match expected pattern")
                expectation.fulfill()
            }
        }
        
        // Cancel all requests at once
        await manager.cancel(requests: requests)
        
        await fulfillment(of: [expectation], timeout: 5)
        
        // Verify all requests are cleaned up
        let finalCurrentDownloadCount = await manager.currentDownloadCount
        XCTAssertEqual(finalCurrentDownloadCount, 0, "No downloads should be current after large array cancellation")
        
        let finalQueuedDownloadCount = await manager.queuedDownloadCount
        XCTAssertEqual(finalQueuedDownloadCount, 0, "No downloads should be queued after large array cancellation")
    }
}
