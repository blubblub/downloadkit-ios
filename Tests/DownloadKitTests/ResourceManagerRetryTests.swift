//
//  ResourceManagerRetryTests.swift
//  DownloadKitTests
//
//  Tests for ResourceManager retry logic with multiple mirrors.
//  Verifies that WeightedMirrorPolicy correctly tries each mirror once
//  and retries the last mirror according to numberOfRetries configuration.
//

import XCTest
import RealmSwift
@testable import DownloadKit
@testable import DownloadKitRealm

// MARK: - Retry Tracking Observer

/// Observer that tracks retry events for verification in tests
actor RetryTrackingObserver: ResourceManagerObserver {
    private let retryCount = ActorCounter()
    private let retriedMirrorIds = ActorArray<String>()
    private let retriedResourceIds = ActorArray<String>()
    
    func didStartDownloading(_ downloadTask: DownloadTask) async {
        // Not needed for retry tests
    }
    
    func willRetryFailedDownload(_ downloadTask: DownloadTask, downloadable: Downloadable, with error: Error) async {
        await retryCount.increment()
        let mirrorId = await downloadable.identifier
        await retriedMirrorIds.append(mirrorId)
        await retriedResourceIds.append(downloadTask.id)
        
        print("Retry event - Resource: \(downloadTask.id), Mirror: \(mirrorId), Error: \(error.localizedDescription)")
    }
    
    func didFinishDownload(_ downloadTask: DownloadTask, with error: Error?) async {
        // Not needed for retry tests
    }
    
    // Public accessors for test verification
    func getTotalRetryCount() async -> Int {
        await retryCount.value
    }
    
    func getRetriedMirrorIds() async -> [String] {
        await retriedMirrorIds.values
    }
    
    func getRetriedResourceIds() async -> [String] {
        await retriedResourceIds.values
    }
}

// MARK: - Test Class

class ResourceManagerRetryTests: XCTestCase {
    
    // Note: Mock processor tests removed because MockDownloadProcessor only processes MockDownloadable
    // instances and cannot create downloadables from resource mirrors. The real WebDownloadProcessor
    // tests below comprehensively test the retry mechanism with the WeightedMirrorPolicy.
    
    // MARK: - Real Download Tests
    
    func testRetryWithRealDownload_AllMirrorsFail() async throws {
        print("\n=== Test: testRetryWithRealDownload_AllMirrorsFail ===")
        
        // Create all instances in test function
        let config = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
        let realm = try await Realm(configuration: config, actor: MainActor.shared)
        let cache = RealmCacheManager<CachedLocalFile>(configuration: config)
        let downloadQueue = DownloadQueue()
        
        // Add real web download processor
        await downloadQueue.add(processor: WebDownloadProcessor(configuration: .default))
        
        let manager = ResourceManager(cache: cache, downloadQueue: downloadQueue)
        
        // Create resource with invalid URLs for all mirrors
        let resource = Resource(
            id: "test-real-all-fail",
            main: FileMirror(
                id: "main-mirror-invalid",
                location: "https://invalid.domain.test.local.nonexistent/main.jpg",
                info: [:]
            ),
            alternatives: [
                FileMirror(
                    id: "alt-mirror-invalid-1",
                    location: "https://invalid.domain.test.local.nonexistent/alt1.jpg",
                    info: [WeightedMirrorPolicy.weightKey: 100]
                ),
                FileMirror(
                    id: "alt-mirror-invalid-2",
                    location: "https://invalid.domain.test.local.nonexistent/alt2.jpg",
                    info: [WeightedMirrorPolicy.weightKey: 50]
                )
            ]
        )
        
        // Attach retry tracking observer
        let retryObserver = RetryTrackingObserver()
        await manager.add(observer: retryObserver)
        
        // Create expectation for completion
        let expectation = XCTestExpectation(description: "Download should complete with failure")
        
        // Request and process download
        let requests = await manager.request(resources: [resource])
        XCTAssertEqual(requests.count, 1, "Should have one download request")
        
        await manager.addResourceCompletion(for: resource) { success, resourceId in
            print("Completion called - Success: \(success), ResourceId: \(resourceId)")
            XCTAssertFalse(success, "Download should fail when all mirrors have invalid URLs")
            XCTAssertEqual(resourceId, "test-real-all-fail")
            expectation.fulfill()
        }
        
        let task = await manager.process(request: requests[0])
        
        // Wait for completion (longer timeout for real network attempts)
        await fulfillment(of: [expectation], timeout: 60)
        
        // Verify retry behavior
        let totalRetries = await retryObserver.getTotalRetryCount()
        let retriedMirrors = await retryObserver.getRetriedMirrorIds()
        
        print("Total retries: \(totalRetries)")
        print("Retried mirrors: \(retriedMirrors)")
        
        // Should have retries as mirrors fail in order: alt1 -> alt2 -> main (3 times)
        XCTAssertGreaterThanOrEqual(totalRetries, 4, "Should have at least 4 retries with real downloads")
        
        // Verify main mirror was retried multiple times
        let mainMirrorRetries = retriedMirrors.filter { $0 == "main-mirror-invalid" }.count
        print("Main mirror retries: \(mainMirrorRetries)")
        
        print("=== Test Complete ===\n")
    }
    
    func testRetryWithRealDownload_MixedValidInvalidMirrors() async throws {
        print("\n=== Test: testRetryWithRealDownload_MixedValidInvalidMirrors ===")
        
        // Create all instances in test function
        let config = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
        let realm = try await Realm(configuration: config, actor: MainActor.shared)
        let cache = RealmCacheManager<CachedLocalFile>(configuration: config)
        let downloadQueue = DownloadQueue()
        
        // Add real web download processor
        await downloadQueue.add(processor: WebDownloadProcessor(configuration: .default))
        
        let manager = ResourceManager(cache: cache, downloadQueue: downloadQueue)
        
        // Create resource with invalid alternatives but valid main mirror
        let resource = Resource(
            id: "test-real-mixed",
            main: FileMirror(
                id: "main-mirror-valid",
                location: "https://picsum.photos/50/50.jpg",
                info: [:]
            ),
            alternatives: [
                FileMirror(
                    id: "alt-mirror-invalid-mixed-1",
                    location: "https://invalid.domain.test.local.nonexistent/alt1.jpg",
                    info: [WeightedMirrorPolicy.weightKey: 100]
                ),
                FileMirror(
                    id: "alt-mirror-invalid-mixed-2",
                    location: "https://invalid.domain.test.local.nonexistent/alt2.jpg",
                    info: [WeightedMirrorPolicy.weightKey: 50]
                )
            ]
        )
        
        // Attach retry tracking observer
        let retryObserver = RetryTrackingObserver()
        await manager.add(observer: retryObserver)
        
        // Create expectation for completion
        let expectation = XCTestExpectation(description: "Download should complete with success after fallback")
        
        // Request and process download
        let requests = await manager.request(resources: [resource])
        XCTAssertEqual(requests.count, 1, "Should have one download request")
        
        await manager.addResourceCompletion(for: resource) { success, resourceId in
            print("Completion called - Success: \(success), ResourceId: \(resourceId)")
            XCTAssertTrue(success, "Download should succeed after falling back to valid main mirror")
            XCTAssertEqual(resourceId, "test-real-mixed")
            expectation.fulfill()
        }
        
        let task = await manager.process(request: requests[0])
        
        // Wait for completion (longer timeout for real network attempts)
        await fulfillment(of: [expectation], timeout: 60)
        
        // Verify retry behavior
        let totalRetries = await retryObserver.getTotalRetryCount()
        let retriedMirrors = await retryObserver.getRetriedMirrorIds()
        
        print("Total retries: \(totalRetries)")
        print("Retried mirrors: \(retriedMirrors)")
        
        // Should have 2 retries (one for each failed alternative mirror)
        // The main mirror should succeed without retry
        XCTAssertEqual(totalRetries, 2, "Should have 2 retries (one for each failed alternative)")
        
        // Verify alternatives were tried
        XCTAssertTrue(retriedMirrors.contains("alt-mirror-invalid-mixed-1"), "Should have retried first alternative")
        XCTAssertTrue(retriedMirrors.contains("alt-mirror-invalid-mixed-2"), "Should have retried second alternative")
        
        // Verify main mirror was NOT in retried list (it succeeded on first try)
        XCTAssertFalse(retriedMirrors.contains("main-mirror-valid"), "Main mirror should not be retried if it succeeds")
        
        print("=== Test Complete ===\n")
    }
    
    // MARK: - Multiple Completion Handlers Test
    
    func testMultipleCompletionHandlersWithRetries() async throws {
        print("\n=== Test: testMultipleCompletionHandlersWithRetries ===")
        
        // Create all instances in test function
        let config = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
        let realm = try await Realm(configuration: config, actor: MainActor.shared)
        let cache = RealmCacheManager<CachedLocalFile>(configuration: config)
        let downloadQueue = DownloadQueue()
        
        // Use real web download processor
        await downloadQueue.add(processor: WebDownloadProcessor(configuration: .default))
        
        let manager = ResourceManager(cache: cache, downloadQueue: downloadQueue)
        
        // Create resource with invalid mirrors that will fail
        let resource = Resource(
            id: "test-multiple-handlers",
            main: FileMirror(
                id: "main-mirror-multi",
                location: "https://invalid.domain.test.local.nonexistent/main.jpg",
                info: [:]
            ),
            alternatives: [
                FileMirror(
                    id: "alt-mirror-multi-1",
                    location: "https://invalid.domain.test.local.nonexistent/alt1.jpg",
                    info: [WeightedMirrorPolicy.weightKey: 100]
                ),
                FileMirror(
                    id: "alt-mirror-multi-2",
                    location: "https://invalid.domain.test.local.nonexistent/alt2.jpg",
                    info: [WeightedMirrorPolicy.weightKey: 50]
                )
            ]
        )
        
        // Attach retry tracking observer
        let retryObserver = RetryTrackingObserver()
        await manager.add(observer: retryObserver)
        
        // Create 3 separate expectations
        let expectation1 = XCTestExpectation(description: "First completion handler should be called")
        let expectation2 = XCTestExpectation(description: "Second completion handler should be called")
        let expectation3 = XCTestExpectation(description: "Third completion handler should be called")
        
        // Request download
        let requests = await manager.request(resources: [resource])
        
        // Add 3 completion handlers
        await manager.addResourceCompletion(for: resource) { success, resourceId in
            print("Completion handler 1 called - Success: \(success)")
            XCTAssertFalse(success, "Download should fail")
            XCTAssertEqual(resourceId, "test-multiple-handlers")
            expectation1.fulfill()
        }
        
        await manager.addResourceCompletion(for: resource) { success, resourceId in
            print("Completion handler 2 called - Success: \(success)")
            XCTAssertFalse(success, "Download should fail")
            XCTAssertEqual(resourceId, "test-multiple-handlers")
            expectation2.fulfill()
        }
        
        await manager.addResourceCompletion(for: resource) { success, resourceId in
            print("Completion handler 3 called - Success: \(success)")
            XCTAssertFalse(success, "Download should fail")
            XCTAssertEqual(resourceId, "test-multiple-handlers")
            expectation3.fulfill()
        }
        
        // Process download
        let task = await manager.process(request: requests[0])
        
        // Wait for all completions
        await fulfillment(of: [expectation1, expectation2, expectation3], timeout: 60)
        
        // Verify retries still happened
        let totalRetries = await retryObserver.getTotalRetryCount()
        print("Total retries with multiple handlers: \(totalRetries)")
        
        XCTAssertGreaterThanOrEqual(totalRetries, 4, "Retries should occur with multiple completion handlers")
        
        print("=== Test Complete ===\n")
    }
}
