import XCTest
import XCTest
import RealmSwift
import os
@testable import DownloadKit
@testable import DownloadKitRealm
@testable import DownloadKitCore

private struct ResourceManagerWrapper {
    let manager: ResourceManager
    let realm: Realm
}

private let log = Logger(subsystem: "DownloadKitTests", category: "MultipleRequestCancellationTests")

class MultipleRequestCancellationTests: XCTestCase {
    
    override func setUpWithError() throws {
        // Synchronous setup - manager will be configured in async test methods
    }
    
    private func setupManager() async -> ResourceManagerWrapper {
        let downloadQueue = DownloadQueue()
        await downloadQueue.add(processor: WebDownloadProcessor(configuration: .default))
        
        // Use in-memory configuration to avoid cache conflicts
        let config = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
        
        // Create Realm instance and keep it alive during the test, so memory is not cleared.
        let realm = try! await Realm(configuration: config, actor: MainActor.shared)
        
        let cache = RealmCacheManager<CachedLocalFile>(configuration: config)
        let manager = ResourceManager(cache: cache, downloadQueue: downloadQueue)
        
        return ResourceManagerWrapper(manager: manager, realm: realm)
    }
    
    private func setupMockManager() async -> ResourceManagerWrapper {
        let downloadQueue = DownloadQueue()
        await downloadQueue.add(processor: MockDownloadProcessor())
        
        // Use in-memory configuration to avoid cache conflicts
        let config = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
        
        // Create Realm instance and keep it alive during the test, so memory is not cleared.
        let realm = try! await Realm(configuration: config, actor: MainActor.shared)
        
        let cache = RealmCacheManager<CachedLocalFile>(configuration: config)
        let manager = ResourceManager(cache: cache, downloadQueue: downloadQueue)
        
        return ResourceManagerWrapper(manager: manager, realm: realm)
    }
    
    private func setupWithPriorityQueue() async -> ResourceManagerWrapper {
        let downloadQueue = DownloadQueue()
        await downloadQueue.add(processor: WebDownloadProcessor(configuration: .default))
        
        let priorityQueue = DownloadQueue()
        await priorityQueue.add(processor: WebDownloadProcessor.priorityProcessor())
        
        // Use in-memory configuration to avoid cache conflicts
        let config = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
        
        // Create Realm instance and keep it alive during the test
        let realm = try! await Realm(configuration: config, actor: MainActor.shared)
        
        let cache = RealmCacheManager<CachedLocalFile>(configuration: config)
        let manager = ResourceManager(cache: cache, downloadQueue: downloadQueue, priorityQueue: priorityQueue)
        
        return ResourceManagerWrapper(manager: manager, realm: realm)
    }
    
    // MARK: - Empty Array Tests
    
    func testCancelEmptyArray() async {
        let wrapper = await setupManager()
        let manager = wrapper.manager
        
        // Test that cancelling empty array doesn't crash or cause issues
        await manager.cancel(downloadTasks: [])
        
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
        let wrapper = await setupManager()
        let manager = wrapper.manager
        
        let resource = Resource(id: "single-cancel-test", 
                               main: FileMirror(id: "single-cancel-test",
                                              location: "https://example.com/fakefile.jpg",
                                              info: [:]),
                               alternatives: [])
        
        let request = await manager.request(resource: resource)
        XCTAssertNotNil(request, "Request should be created")
        
        let expectation = self.expectation(description: "Single request cancellation should trigger completion")
        
        await manager.addResourceCompletion(for: resource) { (success: Bool, resourceId: String) in
            XCTAssertFalse(success, "Cancellation should trigger completion with success: false")
            XCTAssertEqual(resourceId, "single-cancel-test", "Resource ID should match")
            expectation.fulfill()
        }
        
        // Process and get task
        let tasks = await manager.process(requests: [request!])
        XCTAssertEqual(tasks.count, 1, "Should have one task")
        let task = tasks.first!
        
        // Cancel using array method with single request
        await manager.cancel(downloadTasks: [task])
        
        await fulfillment(of: [expectation], timeout: 2)
        
        // Verify state cleanup
        let isDownloading = await manager.isDownloading(for: task.id)
        XCTAssertFalse(isDownloading, "Download should no longer be in progress after cancellation")
        
        let hasDownload = await manager.hasDownload(for: task.id)
        XCTAssertFalse(hasDownload, "Download should be removed from queue after cancellation")
    }
    
    // MARK: - Multiple Request Array Tests
    
    func testCancelMultipleRequestsArray() async {
        let wrapper = await setupManager()
        let manager = wrapper.manager
        
        let resources = [
            Resource(id: "multi-cancel-test-1", 
                    main: FileMirror(id: "multi-cancel-test-1",
                                   location: "https://example.com/fakefile1.jpg",
                                   info: [:]),
                    alternatives: []),
            Resource(id: "multi-cancel-test-2", 
                    main: FileMirror(id: "multi-cancel-test-2",
                                   location: "https://example.com/fakefile2.jpg",
                                   info: [:]),
                    alternatives: []),
            Resource(id: "multi-cancel-test-3", 
                    main: FileMirror(id: "multi-cancel-test-3",
                                   location: "https://example.com/fakefile3.jpg",
                                   info: [:]),
                    alternatives: [])
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
        
        // Process and get tasks
        let tasks = await manager.process(requests: requests)
        XCTAssertEqual(tasks.count, 3, "Should have 3 tasks")
        
        // Cancel all requests using array method
        await manager.cancel(downloadTasks: tasks)
        
        await fulfillment(of: [expectation], timeout: 2)
        
        // Verify all requests are cleaned up
        for task in tasks {
            log.debug("Checking if task is downloading: \(task.id)")
            let isDownloading = await manager.isDownloading(for: task.id)
            XCTAssertFalse(isDownloading, "Download should no longer be in progress after cancellation: \(task.id)")
            
            log.debug("Checking if task is in queue: \(task.id)")
            
            let hasDownload = await manager.hasDownload(for: task.id)
            XCTAssertFalse(hasDownload, "Download should be removed from queue after cancellation: \(task.id)")
        }
    }
    
    // MARK: - Callback Triggering Tests
    
    func testCancelMultipleRequestsTriggersAllCallbacks() async {
        let wrapper = await setupManager()
        let manager = wrapper.manager
        
        let resources = [
            Resource(id: "callback-test-1", 
                    main: FileMirror(id: "callback-test-1",
                                   location: "https://example.com/fakefile1.jpg",
                                   info: [:]),
                    alternatives: []),
            Resource(id: "callback-test-2", 
                    main: FileMirror(id: "callback-test-2",
                                   location: "https://example.com/fakefile2.jpg",
                                   info: [:]),
                    alternatives: [])
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
                if resource.id == resourceId {
                    XCTAssertFalse(success, "Cancellation should trigger completion with success: false")
                    Task {
                        await callbackCounter.increment()
                        await callbackIds.append(resourceId)
                    }
                    expectation.fulfill()
                }
            }
            
            await manager.addResourceCompletion(for: resource) { (success: Bool, resourceId: String) in
                if resource.id == resourceId {
                    XCTAssertFalse(success, "Cancellation should trigger completion with success: false")
                    Task {
                        await callbackCounter.increment()
                        await callbackIds.append(resourceId)
                    }
                    expectation.fulfill()
                }
            }
        }
        
        // Process and get tasks
        let tasks = await manager.process(requests: requests)
        
        // Cancel all requests
        await manager.cancel(downloadTasks: tasks)
        
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
        let wrapper = await setupManager()
        let manager = wrapper.manager
        
        let resources = [
            Resource(id: "state-test-1", 
                    main: FileMirror(id: "state-test-1",
                                   location: "https://example.com/fakefile1.jpg",
                                   info: [:]),
                    alternatives: []),
            Resource(id: "state-test-2", 
                    main: FileMirror(id: "state-test-2",
                                   location: "https://example.com/fakefile2.jpg",
                                   info: [:]),
                    alternatives: []),
            Resource(id: "state-test-3", 
                    main: FileMirror(id: "state-test-3",
                                   location: "https://example.com/fakefile3.jpg",
                                   info: [:]),
                    alternatives: [])
        ]
        
        let requests = await manager.request(resources: resources)
        XCTAssertEqual(requests.count, 3, "Should have 3 requests")
        
        // Process and get tasks
        let tasks = await manager.process(requests: requests)
        
        // Cancel all requests
        await manager.cancel(downloadTasks: tasks, waitUntilCancelled: true)
        
        //log.debug("Completed cancellation.")
        
        // Verify manager state is cleaned up
        let currentDownloadCount = await manager.currentDownloadCount
        XCTAssertEqual(currentDownloadCount, 0, "No downloads should be current after cancellation")
        
        let queuedDownloadCount = await manager.queuedDownloadCount
        XCTAssertEqual(queuedDownloadCount, 0, "No downloads should be queued after cancellation")
        
        let totalDownloads = await manager.downloads.count
        XCTAssertEqual(totalDownloads, 0, "No downloads should exist after cancellation")
        
        // Verify individual request states
        for task in tasks {
            let isDownloading = await manager.isDownloading(for: task.id)
            XCTAssertFalse(isDownloading, "Individual request should not be downloading after cancellation")
            
            let hasDownload = await manager.hasDownload(for: task.id)
            XCTAssertFalse(hasDownload, "Individual request should not have downloadable after cancellation")
        }
    }
    
    // MARK: - Progress Tracking Tests
    
    func testCancelMultipleRequestsProgressTracking() async {
        let wrapper = await setupManager()
        let manager = wrapper.manager
        
        let resources = [
            Resource(id: "progress-test-1", 
                    main: FileMirror(id: "progress-test-1",
                                   location: "https://example.com/fakefile1.jpg",
                                   info: [:]),
                    alternatives: []),
            Resource(id: "progress-test-2", 
                    main: FileMirror(id: "progress-test-2",
                                   location: "https://example.com/fakefile2.jpg",
                                   info: [:]),
                    alternatives: [])
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
        
        // Process and get tasks
        let tasks = await manager.process(requests: requests)
        
        // Cancel all requests
        await manager.cancel(downloadTasks: tasks)
        
        await fulfillment(of: [expectation], timeout: 2)
        
        // Verify progress tracking is cleaned up for all requests
        for task in tasks {
            let progressAfter = await manager.progress.progresses[task.id]
            XCTAssertNil(progressAfter, "Progress should be cleaned up after cancellation for \(task.id)")
        }
    }
    
    // MARK: - Priority Queue Tests
    
    func testCancelMultipleRequestsWithPriorityQueue() async {
        let wrapper = await setupWithPriorityQueue()
        let manager = wrapper.manager
        
        let resources = [
            Resource(id: "priority-cancel-test-1", 
                    main: FileMirror(id: "priority-cancel-test-1",
                                   location: "https://example.com/fakefile1.jpg",
                                   info: [:]),
                    alternatives: []),
            Resource(id: "priority-cancel-test-2", 
                    main: FileMirror(id: "priority-cancel-test-2",
                                   location: "https://example.com/fakefile2.jpg",
                                   info: [:]),
                    alternatives: [])
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
        
        // Process and get tasks
        let tasks = await manager.process(requests: requests)
        
        // Cancel all requests
        await manager.cancel(downloadTasks: tasks)
        
        await fulfillment(of: [expectation], timeout: 2)
        
        // Verify requests are cleaned up from both normal and priority queues
        for task in tasks {
            let isDownloading = await manager.isDownloading(for: task.id)
            XCTAssertFalse(isDownloading, "Download should not be in progress after cancellation")
            
            let hasDownload = await manager.hasDownload(for: task.id)
            XCTAssertFalse(hasDownload, "Download should be removed from both queues after cancellation")
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testCancelRequestArrayWithMixedValidInvalidRequests() async {
        let wrapper = await setupManager()
        let manager = wrapper.manager
        
        let validResource = Resource(id: "valid-mixed-test", 
                                   main: FileMirror(id: "valid-mixed-test",
                                                  location: "https://example.com/fakefile.jpg",
                                                  info: [:]),
                                   alternatives: [])
        
        let validRequest = await manager.request(resource: validResource)
        XCTAssertNotNil(validRequest, "Valid request should be created")
        
        // Create a request for a resource that doesn't exist in the cache
        let invalidResource = Resource(id: "invalid-mixed-test", 
                                     main: FileMirror(id: "invalid-mixed-test",
                                                    location: "https://example.com/fakefile.jpg",
                                                    info: [:]),
                                     alternatives: [])
        
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
        
        // Process and get tasks
        let validTask = (await manager.process(requests: [validRequest!])).first!
        let invalidTask = (await manager.process(requests: [invalidRequest!])).first!
        
        // Cancel both requests together
        await manager.cancel(downloadTasks: [validTask, invalidTask])
        
        await fulfillment(of: [expectation], timeout: 2)
    }
    
    // MARK: - Large Array Tests
    
    func testCancelLargeArrayOfRequests() async {
        let wrapper = await setupManager()
        let manager = wrapper.manager
        
        // Create a large number of resources
        let resources = (1...50).map { index in
            Resource(id: "large-array-test-\(index)", 
                    main: FileMirror(id: "large-array-test-\(index)",
                                   location: "https://example.com/fakefile\(index).jpg",
                                   info: [:]),
                    alternatives: [])
        }
        
        let requests = await manager.request(resources: resources)
        XCTAssertEqual(requests.count, 50, "Should have 50 requests")
        
        let expectation = self.expectation(description: "Large array cancellation should work")
        expectation.expectedFulfillmentCount = 50
        
        // Add completion handlers for all resources
        for resource in resources {
            await manager.addResourceCompletion(for: resource) { (success: Bool, resourceId: String) in
                XCTAssertFalse(success, "Cancellation should trigger completion with success: false: \(resourceId)")
                XCTAssertTrue(resourceId.hasPrefix("large-array-test-"), "Resource ID should match expected pattern: \(resourceId)")
                expectation.fulfill()
            }
        }
        
        // Process and get tasks
        let tasks = await manager.process(requests: requests)
        
        // Cancel all requests at once
        await manager.cancel(downloadTasks: tasks)
        
        await fulfillment(of: [expectation], timeout: 5)
        
        // Verify all requests are cleaned up
        let finalCurrentDownloadCount = await manager.currentDownloadCount
        XCTAssertEqual(finalCurrentDownloadCount, 0, "No downloads should be current after large array cancellation")
        
        let finalQueuedDownloadCount = await manager.queuedDownloadCount
        XCTAssertEqual(finalQueuedDownloadCount, 0, "No downloads should be queued after large array cancellation")
    }
    
    // MARK: - Callback Error Verification Tests
    
    func testCancelledWebDownloadTriggersWaitTillCompleteWithCorrectError() async {
        let wrapper = await setupManager()
        let manager = wrapper.manager
        
        // Create a resource with a real URL that will take time to download
        let resource = Resource(
            id: "web-cancel-wait-error-test",
            main: FileMirror(id: "web-cancel-wait-error-test",
                           location: "https://file-examples.com/storage/fe3aa38b1868ec9b7a1cc78/2017/04/file_example_MP4_1920_18MG.mp4",
                           info: [:]),
            alternatives: []
        )
        
        let request = await manager.request(resource: resource)
        XCTAssertNotNil(request, "Request should be created")
        
        let task = await manager.process(request: request!)
        
        // Start waiting on the task in a separate Task
        let waitTask = Task {
            do {
                try await task.waitTillComplete()
                XCTFail("Should have thrown cancellation error")
            } catch let error as DownloadKitError {
                // Verify the error is specifically network cancelled
                if case .networkError(let networkError) = error {
                    XCTAssertEqual(networkError, .cancelled, "Error should be NetworkError.cancelled")
                } else {
                    XCTFail("Error should be networkError(.cancelled), got: \(error)")
                }
            } catch {
                XCTFail("Unexpected error type: \(error)")
            }
        }
        
        // Give the download time to start
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        // Cancel the download
        await manager.cancel(task)
        
        // Wait for the waitTask to complete
        await waitTask.value
    }
    
    func testCancelledWebDownloadWithMultipleCallbacksVerifyError() async {
        let wrapper = await setupManager()
        let manager = wrapper.manager
        
        let resource = Resource(
            id: "web-multi-callback-test",
            main: FileMirror(id: "web-multi-callback-test",
                           location: "https://file-examples.com/storage/fe3aa38b1868ec9b7a1cc78/2017/04/file_example_MP4_1920_18MG.mp4",
                           info: [:]),
            alternatives: []
        )
        
        let expectation1 = self.expectation(description: "First callback should be triggered")
        let expectation2 = self.expectation(description: "Second callback should be triggered")
        
        // Add multiple resource completion callbacks
        await manager.addResourceCompletion(for: resource) { (success: Bool, resourceId: String) in
            XCTAssertFalse(success, "Cancellation should trigger completion with success: false")
            expectation1.fulfill()
        }
        
        await manager.addResourceCompletion(for: resource) { (success: Bool, resourceId: String) in
            XCTAssertFalse(success, "Cancellation should trigger completion with success: false")
            expectation2.fulfill()
        }
        
        let request = await manager.request(resource: resource)
        XCTAssertNotNil(request, "Request should be created")
        
        let task = await manager.process(request: request!)
        
        // Also test waitTillComplete in parallel
        let waitTask = Task {
            do {
                try await task.waitTillComplete()
                XCTFail("Should have thrown cancellation error")
            } catch let error as DownloadKitError {
                log.debug("Catched error: \(error)")
                if case .networkError(let networkError) = error {
                    XCTAssertEqual(networkError, .cancelled, "Error should be NetworkError.cancelled")
                } else {
                    XCTFail("Error should be networkError(.cancelled), got: \(error)")
                }
            } catch {
                XCTFail("Unexpected error type: \(error)")
            }
        }
        
        // Give the download time to start
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        // Cancel the download
        await manager.cancel(task)
        
        // Wait for both callbacks and the waitTask
        await fulfillment(of: [expectation1, expectation2], timeout: 5)
        await waitTask.value
    }
    
    func testCancelMultipleWebDownloadsVerifyAllCallbacks() async {
        let wrapper = await setupManager()
        let manager = wrapper.manager
        
        // Create web resources
        let webResource1 = Resource(
            id: "mixed-web-1",
            main: FileMirror(id: "mixed-web-1",
                           location: "https://file-examples.com/storage/fe3aa38b1868ec9b7a1cc78/2017/04/file_example_MP4_1920_18MG.mp4",
                           info: [:]),
            alternatives: []
        )
        
        let webResource2 = Resource(
            id: "mixed-web-2",
            main: FileMirror(id: "mixed-web-2",
                           location: "https://file-examples.com/storage/fe3aa38b1868ec9b7a1cc78/2017/04/file_example_MP4_1920_18MG.mp4",
                           info: [:]),
            alternatives: []
        )
        
        let webResource3 = Resource(
            id: "mixed-web-3",
            main: FileMirror(id: "mixed-web-3",
                           location: "https://file-examples.com/storage/fe3aa38b1868ec9b7a1cc78/2017/04/file_example_MP4_1920_18MG.mp4",
                           info: [:]),
            alternatives: []
        )
        
        let expectation = self.expectation(description: "All callbacks should be triggered")
        expectation.expectedFulfillmentCount = 3
        
        // Add callbacks for all resources
        await manager.addResourceCompletion(for: webResource1) { (success: Bool, resourceId: String) in
            XCTAssertFalse(success, "Cancellation should trigger completion with success: false")
            expectation.fulfill()
        }
        
        await manager.addResourceCompletion(for: webResource2) { (success: Bool, resourceId: String) in
            XCTAssertFalse(success, "Cancellation should trigger completion with success: false")
            expectation.fulfill()
        }
        
        await manager.addResourceCompletion(for: webResource3) { (success: Bool, resourceId: String) in
            XCTAssertFalse(success, "Cancellation should trigger completion with success: false")
            expectation.fulfill()
        }
        
        // Request and process all downloads
        let webRequest1 = await manager.request(resource: webResource1)
        let webRequest2 = await manager.request(resource: webResource2)
        let webRequest3 = await manager.request(resource: webResource3)
        
        let webTask1 = await manager.process(request: webRequest1!)
        let webTask2 = await manager.process(request: webRequest2!)
        let webTask3 = await manager.process(request: webRequest3!)
        
        let tasks = [webTask1, webTask2, webTask3]
        
        // Give downloads time to start
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        // Cancel all downloads
        await manager.cancel(downloadTasks: tasks)
        
        await fulfillment(of: [expectation], timeout: 5)
    }
}
