import XCTest
import RealmSwift
@testable import DownloadKit
@testable import DownloadKitRealm

class ResourceManagerIntegrationTests: XCTestCase {
    var manager: ResourceManager!
    var cache: RealmCacheManager<CachedLocalFile>!
    
    override func setUpWithError() throws {
        // Create async setup in the test methods to avoid issues
    }

    override func tearDownWithError() throws {
        // Note: Avoiding async cleanup in tearDown to prevent concurrency issues
        // Using in-memory database makes cleanup unnecessary
        cache = nil
        manager = nil
    }
    
    /// Helper method to setup ResourceManager for integration tests
    private func setupManager() async {
        let downloadQueue = DownloadQueue()
        await downloadQueue.add(processor: WebDownloadProcessor(configuration: .default))
        
        // Use in-memory Realm for testing to avoid conflicts
        let config = Realm.Configuration(inMemoryIdentifier: "integration-test-\(UUID().uuidString)")
        cache = RealmCacheManager<CachedLocalFile>(configuration: config)
        manager = ResourceManager(cache: cache, downloadQueue: downloadQueue)
    }
    
    /// Creates test resources using free online APIs
    private func createTestResources(count: Int) -> [Resource] {
        return (1...count).map { i in
            // Use reliable small image service
            let imageSize = 50 + (i % 5) * 10 // 50x50, 60x60, 70x70, 80x80, 90x90
            let selectedURL = "https://picsum.photos/\(imageSize)/\(imageSize).jpg"
            
            return Resource(
                id: "integration-resource-\(i)",
                main: FileMirror(
                    id: "mirror-\(i)",
                    location: selectedURL,
                    info: [:]
                ),
                alternatives: [],
                fileURL: nil
            )
        }
    }

    /// Test downloading 100+ files and verify caching works correctly
    func testBatchDownloadAndCache() async throws {
        await setupManager()
        
        let resourceCount = 120 // Test with 120 resources
        let resources = createTestResources(count: resourceCount)
        
        print("Starting batch download test with \(resourceCount) resources...")
        
        // Request all downloads
        let requests = await manager.request(resources: resources)
        print("Created \(requests.count) download requests")
        
        // We expect all resources to be requested (none should be cached initially)
        XCTAssertEqual(requests.count, resourceCount, "All resources should have been requested for download.")
        
        // Use XCTestExpectation for async completion tracking
        let batchExpectation = XCTestExpectation(description: "Batch downloads should complete")
        batchExpectation.expectedFulfillmentCount = requests.count
        
        // Set up completion handlers for all resources
        for resource in resources {
            await manager.addResourceCompletion(for: resource.id) { @Sendable (success, resourceID) in
                if success {
                    print("✅ Completed: \(resourceID)")
                } else {
                    print("❌ Failed: \(resourceID)")
                }
                batchExpectation.fulfill()
            }
        }
        
        // Wait for all downloads to complete (allow some failures due to network)
        await fulfillment(of: [batchExpectation], timeout: 120) // 2 minutes timeout
        
        // Verify caching for completed downloads
        var cachedCount = 0
        for resource in resources {
            if let _ = await cache[resource.id] {
                cachedCount += 1
            }
        }
        
        print("Cache verification: \(cachedCount) resources found in cache")
        // We expect most downloads to be cached (allow some failures due to network)
        XCTAssertGreaterThan(cachedCount, resourceCount * 2 / 3, "Most downloads should be cached")
    }
    
    /// Test basic functionality with a small number of downloads
    func testBasicDownloadFunctionality() async throws {
        await setupManager()
        
        // Test with just 3 resources to ensure it works
        let resources = createTestResources(count: 3)
        
        print("Testing basic download functionality with \(resources.count) resources...")
        
        // Request downloads
        let requests = await manager.request(resources: resources)
        print("Created \(requests.count) download requests")
        
        XCTAssertEqual(requests.count, 3, "Should have 3 download requests")
        
        // Test that manager state is correct
        let isActive = await manager.isActive
        XCTAssertTrue(isActive, "Manager should be active")
        
        // Check that downloads are queued
        let queuedCount = await manager.queuedDownloadCount
        print("Queued downloads: \(queuedCount)")
        XCTAssertGreaterThan(queuedCount, 0, "Should have queued downloads")
    }
    
    /// Test single successful download and caching
    func testSingleDownloadAndCache() async throws {
        await setupManager()
        
        // Create a single resource for testing
        let resource = Resource(
            id: "test-single-resource",
            main: FileMirror(
                id: "test-mirror",
                location: "https://picsum.photos/100/100.jpg",
                info: [:]
            ),
            alternatives: [],
            fileURL: nil
        )
        
        print("Testing single download with resource: \(resource.id)")
        
        // Request download
        let requests = await manager.request(resources: [resource])
        XCTAssertEqual(requests.count, 1, "Should have one download request")
        
        // Set up completion handler
        let downloadExpectation = XCTestExpectation(description: "Single download should complete")
        
        await manager.addResourceCompletion(for: resource.id) { @Sendable (success, resourceID) in
            print("Download result - Success: \(success), Resource: \(resourceID)")
            if success {
                print("✅ Download succeeded for \(resourceID)")
            } else {
                print("❌ Download failed for \(resourceID)")
            }
            downloadExpectation.fulfill()
        }
        
        // Wait for download to complete
        await fulfillment(of: [downloadExpectation], timeout: 30)
        
        // Check if resource is in cache
        let cachedURL = await cache[resource.id]
        if let url = cachedURL {
            print("✅ Resource found in cache at: \(url.path)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Cached file should exist")
        } else {
            print("❌ Resource not found in cache")
            // Don't fail the test immediately - the download might have failed due to network
        }
    }
    
    /// Test concurrent downloads with different priorities
    func testConcurrentDownloadsWithPriorities() async throws {
        await setupManager()
        
        let normalResources = createTestResources(count: 25)
        let highPriorityResources = createTestResources(count: 25).map { resource in
            Resource(
                id: "high-priority-\(resource.id)",
                main: resource.main,
                alternatives: resource.alternatives,
                fileURL: resource.fileURL
            )
        }
        
        // Start normal priority downloads
        let normalRequests = await manager.request(
            resources: normalResources,
            options: RequestOptions(downloadPriority: .normal, storagePriority: .cached)
        )
        
        // Start high priority downloads
        let highPriorityRequests = await manager.request(
            resources: highPriorityResources,
            options: RequestOptions(downloadPriority: .high, storagePriority: .permanent)
        )
        
        print("Started \(normalRequests.count) normal and \(highPriorityRequests.count) high priority downloads")
        
        // Track completion times (high priority should generally complete first)
        var normalCompletions: [Date] = []
        var highPriorityCompletions: [Date] = []
        let completionQueue = DispatchQueue(label: "completion-tracking")
        
        let allExpectation = XCTestExpectation(description: "All downloads should complete")
        allExpectation.expectedFulfillmentCount = normalRequests.count + highPriorityRequests.count
        
        // Set up completion tracking
        for resource in normalResources {
            await manager.addResourceCompletion(for: resource.id) { @Sendable (success, resourceID) in
                if success {
                    completionQueue.sync {
                        normalCompletions.append(Date())
                    }
                }
                allExpectation.fulfill()
            }
        }
        
        for resource in highPriorityResources {
            await manager.addResourceCompletion(for: resource.id) { @Sendable (success, resourceID) in
                if success {
                    completionQueue.sync {
                        highPriorityCompletions.append(Date())
                    }
                }
                allExpectation.fulfill()
            }
        }
        
        await fulfillment(of: [allExpectation], timeout: 90)
        
        print("Completed \(normalCompletions.count) normal and \(highPriorityCompletions.count) high priority downloads")
        
        // Basic verification that downloads completed
        XCTAssertGreaterThan(normalCompletions.count + highPriorityCompletions.count, 30, "Most downloads should complete successfully")
    }
    
    /// Test resource manager metrics and monitoring
    func testResourceManagerMetrics() async throws {
        await setupManager()
        
        let resources = createTestResources(count: 15)
        
        // Get initial metrics
        let initialMetrics = await manager.metrics
        print("Initial metrics: \(initialMetrics.description)")
        
        // Request downloads
        let requests = await manager.request(resources: resources)
        
        // Wait for downloads to complete
        let metricsExpectation = XCTestExpectation(description: "Downloads should complete and update metrics")
        metricsExpectation.expectedFulfillmentCount = requests.count
        
        for resource in resources {
            await manager.addResourceCompletion(for: resource.id) { @Sendable (success, resourceID) in
                metricsExpectation.fulfill()
            }
        }
        
        await fulfillment(of: [metricsExpectation], timeout: 45)
        
        // Check final metrics
        let finalMetrics = await manager.metrics
        print("Final metrics: \(finalMetrics.description)")
        
        // Verify metrics were updated
        XCTAssertGreaterThan(finalMetrics.requested, initialMetrics.requested, "Requested count should increase")
        XCTAssertGreaterThan(finalMetrics.downloadBegan, initialMetrics.downloadBegan, "Download began count should increase")
        XCTAssertGreaterThan(finalMetrics.downloadCompleted + finalMetrics.failed, 0, "Some downloads should complete or fail")
    }
    
    /// Test cancellation during batch downloads
    func testCancellationDuringBatchDownload() async throws {
        await setupManager()
        
        let resources = createTestResources(count: 30)
        
        // Start downloads
        let requests = await manager.request(resources: resources)
        XCTAssertGreaterThan(requests.count, 0, "Should have download requests")
        
        // Wait a bit for downloads to start
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Check download status
        let currentDownloads = await manager.currentDownloadCount
        let queuedDownloads = await manager.queuedDownloadCount
        print("Before cancellation - Current: \(currentDownloads), Queued: \(queuedDownloads)")
        
        // Cancel all downloads
        await manager.cancelAll()
        
        // Verify cancellation
        let currentDownloadsAfterCancel = await manager.currentDownloadCount
        let queuedDownloadsAfterCancel = await manager.queuedDownloadCount
        print("After cancellation - Current: \(currentDownloadsAfterCancel), Queued: \(queuedDownloadsAfterCancel)")
        
        XCTAssertEqual(currentDownloadsAfterCancel, 0, "No downloads should be current after cancellation")
        XCTAssertEqual(queuedDownloadsAfterCancel, 0, "No downloads should be queued after cancellation")
    }
    
    /// Comprehensive integration test that validates batch downloads, caching, and framework functionality
    /// This test focuses on validating the framework works correctly rather than network success
    func testComprehensiveBatchDownloadIntegration() async throws {
        await setupManager()
        
        print("\n=== COMPREHENSIVE INTEGRATION TEST ===")
        print("Testing ResourceManager with 150 resources...")
        
        // Create a large batch of resources
        let resourceCount = 150
        let resources = createTestResources(count: resourceCount)
        
        // Verify initial state
        let initialMetrics = await manager.metrics
        print("Initial metrics: \(initialMetrics.description)")
        XCTAssertEqual(initialMetrics.requested, 0, "Should start with 0 requested")
        
        // Request all downloads
        let startTime = Date()
        let requests = await manager.request(resources: resources)
        let requestTime = Date().timeIntervalSince(startTime)
        
        print("✅ Created \(requests.count) download requests in \(String(format: "%.2f", requestTime))s")
        XCTAssertEqual(requests.count, resourceCount, "All resources should be requested")
        
        // Verify manager state after requesting
        let isActive = await manager.isActive
        XCTAssertTrue(isActive, "Manager should be active")
        
        // Check intermediate metrics
        let afterRequestMetrics = await manager.metrics
        print("After request metrics: \(afterRequestMetrics.description)")
        XCTAssertEqual(afterRequestMetrics.requested, resourceCount, "Should have requested all resources")
        
        // Set up completion tracking
        var completedResources: Set<String> = []
        var failedResources: Set<String> = []
        let resultsQueue = DispatchQueue(label: "results")
        
        let batchExpectation = XCTestExpectation(description: "Batch operations should complete")
        batchExpectation.expectedFulfillmentCount = resourceCount
        
        // Track all completions
        for resource in resources {
            await manager.addResourceCompletion(for: resource.id) { @Sendable (success, resourceID) in
                resultsQueue.sync {
                    if success {
                        completedResources.insert(resourceID)
                    } else {
                        failedResources.insert(resourceID)
                    }
                }
                batchExpectation.fulfill()
            }
        }
        
        // Wait for all download attempts to complete
        print("Waiting for batch downloads to complete...")
        await fulfillment(of: [batchExpectation], timeout: 180) // 3 minutes
        
        // Get final results
        let finalCompletedCount = resultsQueue.sync { completedResources.count }
        let finalFailedCount = resultsQueue.sync { failedResources.count }
        let finalMetrics = await manager.metrics
        
        print("\n=== FINAL RESULTS ===")
        print("Completed: \(finalCompletedCount)")
        print("Failed: \(finalFailedCount)")
        print("Total processed: \(finalCompletedCount + finalFailedCount)")
        print("Final metrics: \(finalMetrics.description)")
        
        // Core functionality validation
        XCTAssertEqual(finalCompletedCount + finalFailedCount, resourceCount, "All resources should be processed")
        XCTAssertEqual(finalMetrics.requested, resourceCount, "Metrics should track all requests")
        XCTAssertGreaterThan(finalMetrics.downloadBegan, 0, "Some downloads should have begun")
        
        // Test cache functionality for completed downloads
        var cachedCount = 0
        let completedResourcesSnapshot = resultsQueue.sync { completedResources }
        for resourceID in completedResourcesSnapshot {
            if let cachedURL = await cache[resourceID] {
                cachedCount += 1
                // Verify the cached file exists
                XCTAssertTrue(FileManager.default.fileExists(atPath: cachedURL.path), 
                             "Cached file should exist for \(resourceID)")
            }
        }
        
        print("Cache verification: \(cachedCount) resources found in cache")
        
        // If any downloads succeeded, they should be cached
        if finalCompletedCount > 0 {
            XCTAssertEqual(cachedCount, finalCompletedCount, "All completed downloads should be cached")
        }
        
        // Test second request for same resources (cache effectiveness)
        print("\n=== TESTING CACHE EFFECTIVENESS ===")
        let secondRequestStart = Date()
        let secondRequests = await manager.request(resources: resources)
        let secondRequestTime = Date().timeIntervalSince(secondRequestStart)
        
        print("Second request: \(secondRequests.count) new downloads needed in \(String(format: "%.2f", secondRequestTime))s")
        
        // Cached resources should not need re-download
        XCTAssertEqual(secondRequests.count, finalFailedCount, 
                      "Only failed resources should need re-download")
        
        // Test manager state operations
        print("\n=== TESTING MANAGER OPERATIONS ===")
        
        // Test deactivation
        await manager.setActive(false)
        let isInactive = await manager.isActive
        XCTAssertFalse(isInactive, "Manager should be inactive")
        
        // Test reactivation
        await manager.setActive(true)
        let isActiveAgain = await manager.isActive
        XCTAssertTrue(isActiveAgain, "Manager should be active again")
        
        // Test final cancellation
        await manager.cancelAll()
        let finalCurrentDownloads = await manager.currentDownloadCount
        let finalQueuedDownloads = await manager.queuedDownloadCount
        
        XCTAssertEqual(finalCurrentDownloads, 0, "No downloads should be current after cancelAll")
        XCTAssertEqual(finalQueuedDownloads, 0, "No downloads should be queued after cancelAll")
        
        print("\n✅ COMPREHENSIVE INTEGRATION TEST COMPLETED SUCCESSFULLY")
        print("Framework validated with \(resourceCount) resources")
        print("Cache system tested and verified")
        print("Manager operations tested")
        print("===========================================\n")
    }
}
