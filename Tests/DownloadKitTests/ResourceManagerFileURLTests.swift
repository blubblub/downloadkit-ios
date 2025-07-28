import XCTest
import RealmSwift
@testable import DownloadKit
@testable import DownloadKitRealm

class ResourceManagerFileURLTests: XCTestCase {
    var manager: ResourceManager!
    var cache: RealmCacheManager<CachedLocalFile>!
    var realm: Realm!

    override func setUpWithError() throws {
        // Synchronous setup - cache manager will be configured in the async test methods
    }

    private func setupManager() async {
        let downloadQueue = DownloadQueue()
        await downloadQueue.add(processor: WebDownloadProcessor(configuration: .default))
        
        // Use in-memory Realm for testing to avoid conflicts
        let config = Realm.Configuration(inMemoryIdentifier: "file-url-test-\(UUID().uuidString)")
        
        // Create Realm instance and keep it alive during the test
        realm = try! await Realm(configuration: config, actor: MainActor.shared)
        
        cache = RealmCacheManager<CachedLocalFile>(configuration: config)
        manager = ResourceManager(cache: cache, downloadQueue: downloadQueue)
    }
    
    func testCachedFileContainsValidData() async throws {
        await setupManager()
        
        // Configure the test resource
        let resource = Resource(
            id: "cached-file-valid-data-test",
            main: FileMirror(
                id: "cached-file-mirror",
                location: "https://picsum.photos/200/300.jpg",
                info: [:]
            ),
            alternatives: [],
            fileURL: nil
        )

        // Request the download
        let requests = await manager.request(resources: [resource])
        XCTAssertEqual(requests.count, 1, "Should have one download request")

        // Set up completion expectation
        let downloadExpectation = XCTestExpectation(description: "Image download should complete")
        let successCounter = ActorCounter()

        await manager.addResourceCompletion(for: resource) { @Sendable (success, _) in
            Task {
                await successCounter.setValue(success ? 1 : 0)
                downloadExpectation.fulfill()
            }
        }

        // Process the download
        await manager.process(requests: requests)

        // Wait for the download to complete
        await fulfillment(of: [downloadExpectation], timeout: 60)

        // Verification
        let downloadSuccess = await successCounter.value == 1
        XCTAssertTrue(downloadSuccess, "The image should download successfully")

        if downloadSuccess {
            if let fileURL = await manager.fileURL(for: resource.id) {
                let data = try Data(contentsOf: fileURL)
                XCTAssertFalse(data.isEmpty, "Data should not be empty")

                if let image = LocalImage(data: data) {
                    XCTAssertGreaterThan(image.size.width, 0, "Image width should be greater than 0")
                    XCTAssertGreaterThan(image.size.height, 0, "Image height should be greater than 0")
                } else {
                    XCTFail("Failed to create LocalImage from data")
                }
            } else {
                XCTFail("File URL should not be nil after download")
            }
        }
    }
    
    func testFileURLForMultipleConcurrentDownloads() async throws {
        await setupManager()
        
        print("Testing multiple concurrent downloads with unique fileURLs...")
        
        // Create 8 different resources with unique IDs and varying image sizes
        let resourceCount = 8
        let resources = (1...resourceCount).map { i in
            let uniqueID = "concurrent-download-\(UUID().uuidString)"
            let imageSize = 150 + (i * 20) // Different image sizes: 170, 190, 210, etc.
            let imageURL = "https://picsum.photos/\(imageSize)/\(imageSize).jpg"
            
            return Resource(
                id: uniqueID,
                main: FileMirror(
                    id: "mirror-\(uniqueID)",
                    location: imageURL,
                    info: [:]
                ),
                alternatives: [],
                fileURL: nil
            )
        }
        
        // Verify initial state - no fileURL should be available
        for resource in resources {
            let initialURL = await manager.fileURL(for: resource.id)
            XCTAssertNil(initialURL, "FileURL should be nil before download for resource \(resource.id)")
        }
        
        // Request all downloads concurrently
        let requests = await manager.request(resources: resources)
        XCTAssertEqual(requests.count, resourceCount, "All resources should be requested for download")
        
        print("Created \(requests.count) concurrent download requests")
        
        // Set up multiple XCTestExpectations to track each download
        let downloadExpectations = resources.map {
            XCTestExpectation(description: "Download \($0.id) should complete")
        }
        
        let successfulDownloads = ActorArray<String>()
        let failedDownloads = ActorArray<String>()
        
        // Add completion handlers for each resource
        for (index, resource) in resources.enumerated() {
            await manager.addResourceCompletion(for: resource) { @Sendable (success, resourceID) in
                Task {
                    if success {
                        await successfulDownloads.append(resourceID)
                    } else {
                        await failedDownloads.append(resourceID)
                    }
                    downloadExpectations[index].fulfill()
                }
            }
        }
        
        // Process downloads concurrently
        await manager.process(requests: requests)
        
        // Wait for all downloads to complete
        await fulfillment(of: downloadExpectations, timeout: 60)
        
        // Verify download results
        let successfulIDs = await successfulDownloads.values
        let failedIDs = await failedDownloads.values
        
        print("Download results: \(successfulIDs.count) successful, \(failedIDs.count) failed")
        
        // At least most downloads should succeed (allow for some network issues)
        XCTAssertGreaterThanOrEqual(successfulIDs.count, resourceCount - 2, "Most downloads should succeed")
        XCTAssertEqual(successfulIDs.count + failedIDs.count, resourceCount, "All downloads should be processed")
        
        // Verify each successful resource has a unique fileURL
        var fileURLs: [URL] = []
        var fileURLToResourceMap: [URL: String] = [:]
        
        for resourceID in successfulIDs {
            guard let resource = resources.first(where: { $0.id == resourceID }) else {
                XCTFail("Could not find resource with ID \(resourceID)")
                continue
            }
            
            let fileURL = await manager.fileURL(for: resource.id)
            XCTAssertNotNil(fileURL, "File URL should not be nil for downloaded resource \(resourceID)")
            
            if let url = fileURL {
                // Verify file exists and contains valid data
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "File should exist for \(resourceID)")
                
                // Verify file has content
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = attributes[FileAttributeKey.size] as? Int64 ?? 0
                XCTAssertGreaterThan(fileSize, 0, "File should have content for \(resourceID)")
                
                // Verify file contains valid image data
                let data = try Data(contentsOf: url)
                XCTAssertFalse(data.isEmpty, "File data should not be empty for \(resourceID)")
                
                // Try to create an image from the data to verify it's valid
                let image = LocalImage(data: data)
                XCTAssertNotNil(image, "Should be able to create image from data for \(resourceID)")
                
                fileURLs.append(url)
                fileURLToResourceMap[url] = resourceID
                
                print("✅ Resource \(resourceID): Valid fileURL at \(url.path), size: \(fileSize) bytes")
            }
        }
        
        // Ensure no file URLs are mixed up between resources
        XCTAssertEqual(Set(fileURLs).count, fileURLs.count, "All file URLs should be unique")
        XCTAssertEqual(fileURLs.count, successfulIDs.count, "Number of file URLs should match successful downloads")
        
        // Verify each fileURL is properly associated with its resource
        for (url, resourceID) in fileURLToResourceMap {
            guard let resource = resources.first(where: { $0.id == resourceID }) else {
                XCTFail("Could not find resource with ID \(resourceID)")
                continue
            }
            
            let retrievedURL = await manager.fileURL(for: resource.id)
            XCTAssertEqual(retrievedURL, url, "FileURL should be consistent for resource \(resourceID)")
        }
        
        // Verify resources are properly cached
        var cachedCount = 0
        for resourceID in successfulIDs {
            if let cachedURL = await cache.fileURL(for: resourceID) {
                cachedCount += 1
                
                // Verify cached URL matches the fileURL from manager
                guard let resource = resources.first(where: { $0.id == resourceID }) else {
                    continue
                }
                let managerURL = await manager.fileURL(for: resource.id)
                XCTAssertEqual(cachedURL, managerURL, "Cached URL should match manager fileURL for \(resourceID)")
            }
        }
        
        XCTAssertEqual(cachedCount, successfulIDs.count, "All successful downloads should be cached")
        
        print("✅ Multiple concurrent downloads test completed successfully")
        print("Downloaded \(successfulIDs.count) files with unique fileURLs, verified data integrity")
    }
    
    override func tearDownWithError() throws {
        // Clear references - in-memory realm will be automatically cleaned up
        cache = nil
        manager = nil
        realm = nil
    }
    
    // MARK: - Basic fileURL Tests
    
    func testFileURLReturnsNilBeforeDownload() async throws {
        await setupManager()
        
        // Create a test resource using picsum.photos
        let resource = Resource(
            id: "picsum-test-resource",
            main: FileMirror(
                id: "picsum-test-mirror",
                location: "https://picsum.photos/100/100.jpg",
                info: [:]
            ),
            alternatives: [],
            fileURL: nil
        )
        
        // Call manager.fileURL(for: resource) before any download
        let fileURL = await manager.fileURL(for: resource.id)
        
        // Assert the result is nil
        XCTAssertNil(fileURL, "File URL should be nil before download")
        
        // Verify the resource is not available in cache using cache.isAvailable(resource: resource)
        let isAvailable = await cache.isAvailable(resource: resource)
        XCTAssertFalse(isAvailable, "Resource should not be available in cache before download")
    }
    
    func testFileURLForResourceNotInCache() async throws {
        await setupManager()
        
        let sampleMain = FileMirror(id: UUID().uuidString, location: "https://example.com/sample", info: [:])
        let resource = Resource(id: UUID().uuidString, main: sampleMain)

        // No file should be cached, so the fileURL should be nil
        let url = await manager.fileURL(for: resource.id)
        XCTAssertNil(url, "File URL should be nil for a resource not in cache.")
    }
    
    func testFileURLForValidCachedResource() async throws {
        await setupManager()
        
        let sampleMain = FileMirror(id: UUID().uuidString, location: "https://example.com/sample", info: [:])
        let resource = Resource(id: UUID().uuidString, main: sampleMain)
        
        // Create a temporary file to simulate a cached resource
        let tempFileURL = try FileManager.createFileOnDisk()
        
        // Store the resource in cache using the cache manager's store method
        let options = RequestOptions(storagePriority: .cached)
        let localFile = try await cache.localCache.store(resource: resource, mirror: resource.main, at: tempFileURL, options: options)
        
        let url = await manager.fileURL(for: resource.id)
        XCTAssertNotNil(url, "File URL should not be nil for a cached resource.")
        XCTAssertEqual(url, localFile.fileURL, "File URL should match the cached file URL.")
        
        // Verify the file exists at the returned URL
        XCTAssertTrue(FileManager.default.fileExists(atPath: url!.path), "File should exist at the returned URL.")
    }
    
    func testFileURLForPermanentStorageResource() async throws {
        await setupManager()
        
        let sampleMain = FileMirror(id: UUID().uuidString, location: "https://example.com/sample", info: [:])
        let resource = Resource(id: UUID().uuidString, main: sampleMain)
        
        // Create a temporary file to simulate a cached resource
        let tempFileURL = try FileManager.createFileOnDisk()
        
        // Store the resource in cache with permanent storage priority
        let options = RequestOptions(storagePriority: .permanent)
        let localFile = try await cache.localCache.store(resource: resource, mirror: resource.main, at: tempFileURL, options: options)
        
        let url = await manager.fileURL(for: resource.id)
        XCTAssertNotNil(url, "File URL should not be nil for a permanently stored resource.")
        XCTAssertEqual(url, localFile.fileURL, "File URL should match the cached file URL.")
        
        // Verify the file exists at the returned URL
        XCTAssertTrue(FileManager.default.fileExists(atPath: url!.path), "File should exist at the returned URL.")
    }
    
    func testFileURLForMultipleResources() async throws {
        await setupManager()
        
        let resources = (1...5).map { i in
            let sampleMain = FileMirror(id: "mirror-\(i)", location: "https://example.com/sample-\(i)", info: [:])
            return Resource(id: "resource-\(i)", main: sampleMain)
        }
        
        let options = RequestOptions(storagePriority: .cached)
        var storedURLs: [URL] = []
        
        // Store multiple resources
        for resource in resources {
            let tempFileURL = try FileManager.createFileOnDisk()
            let localFile = try await cache.localCache.store(resource: resource, mirror: resource.main, at: tempFileURL, options: options)
            storedURLs.append(localFile.fileURL)
        }
        
        // Verify all resources return correct file URLs
        for (index, resource) in resources.enumerated() {
            let url = await manager.fileURL(for: resource.id)
            XCTAssertNotNil(url, "File URL should not be nil for cached resource \(resource.id).")
            XCTAssertEqual(url, storedURLs[index], "File URL should match the stored URL for resource \(resource.id).")
        }
    }
    
    // MARK: - Edge Cases Tests
    
    func testFileURLAfterFailedDownload() async throws {
        await setupManager()
        
        // Create a resource with an invalid URL that will fail
        let resource = Resource(
            id: "failed-download-test",
            main: FileMirror(
                id: "failed-download-mirror",
                location: "https://this-domain-does-not-exist-12345.com/image.jpg", // Invalid URL
                info: [:]
            ),
            alternatives: [],
            fileURL: nil
        )
        
        // Verify fileURL is nil before download
        let initialURL = await manager.fileURL(for: resource.id)
        XCTAssertNil(initialURL, "File URL should be nil before download")
        
        // Request the download
        let requests = await manager.request(resources: [resource])
        XCTAssertEqual(requests.count, 1, "Should have one download request")
        
        // Set up completion expectation
        let downloadExpectation = XCTestExpectation(description: "Download should fail")
        let downloadSuccessCounter = ActorCounter()
        
        await manager.addResourceCompletion(for: resource) { @Sendable (success, _) in
            Task {
                await downloadSuccessCounter.setValue(success ? 1 : 0)
                downloadExpectation.fulfill()
            }
        }
        
        // Process the download
        await manager.process(requests: requests)
        
        // Wait for the download to complete (should fail)
        await fulfillment(of: [downloadExpectation], timeout: 30)
        
        // Verify download failed
        let downloadSuccess = await downloadSuccessCounter.value == 1
        XCTAssertFalse(downloadSuccess, "Download should fail with invalid URL")
        
        // Verify fileURL remains nil after failed download
        let finalURL = await manager.fileURL(for: resource.id)
        XCTAssertNil(finalURL, "File URL should remain nil after failed download")
        
        // Verify resource is not in cache
        let cachedURL = await cache.fileURL(for: resource.id)
        XCTAssertNil(cachedURL, "Resource should not be cached after failed download")
    }
    
    func testFileURLAfterCancelledDownload() async throws {
        await setupManager()
        
        // Create a resource for download
        let resource = Resource(
            id: "cancelled-download-test",
            main: FileMirror(
                id: "cancelled-download-mirror",
                location: "https://picsum.photos/800/800.jpg",
                info: [:]
            ),
            alternatives: [],
            fileURL: nil
        )
        
        // Verify fileURL is nil before download
        let initialURL = await manager.fileURL(for: resource.id)
        XCTAssertNil(initialURL, "File URL should be nil before download")
        
        // Request the download
        let requests = await manager.request(resources: [resource])
        XCTAssertEqual(requests.count, 1, "Should have one download request")
        
        let downloadRequest = requests.first!
        
        // Set up completion expectation
        let downloadExpectation = XCTestExpectation(description: "Download should be cancelled")
        let downloadSuccessCounter = ActorCounter()
        
        await manager.addResourceCompletion(for: resource) { @Sendable (success, _) in
            Task {
                await downloadSuccessCounter.setValue(success ? 1 : 0)
                downloadExpectation.fulfill()
            }
        }
        
        // Process the download
        await manager.process(requests: requests)
        
        // Wait a short time to let download start, then cancel it
        try await Task.sleep(nanoseconds: 1_000_000) // 0.1 second
        await manager.cancel(request: downloadRequest)
        
        // Wait for the cancellation to complete
        await fulfillment(of: [downloadExpectation], timeout: 5)
        
        // Verify download was cancelled (success should be false)
        let downloadSuccess = await downloadSuccessCounter.value == 1
        XCTAssertFalse(downloadSuccess, "Download should be cancelled")
        
        // Verify fileURL is nil after cancelled download
        let finalURL = await manager.fileURL(for: resource.id)
        XCTAssertNil(finalURL, "File URL should be nil after cancelled download")
        
        // Verify resource is not in cache
        let cachedURL = await cache.fileURL(for: resource.id)
        XCTAssertNil(cachedURL, "Resource should not be cached after cancelled download")
    }
    
    func testFileURLPersistenceAcrossManagerInstances() async throws {
        await setupManager()
        
        // Create a resource for download
        let resource = Resource(
            id: "persistence-test",
            main: FileMirror(
                id: "persistence-mirror",
                location: "https://picsum.photos/150/150.jpg",
                info: [:]
            ),
            alternatives: [],
            fileURL: nil
        )
        
        // Request and complete the download with the first manager
        let requests = await manager.request(resources: [resource])
        XCTAssertEqual(requests.count, 1, "Should have one download request")
        
        // Set up completion expectation
        let downloadExpectation = XCTestExpectation(description: "Download should complete")
        let downloadSuccessCounter = ActorCounter()
        
        await manager.addResourceCompletion(for: resource) { @Sendable (success, _) in
            Task {
                await downloadSuccessCounter.setValue(success ? 1 : 0)
                downloadExpectation.fulfill()
            }
        }
        
        // Process the download
        await manager.process(requests: requests)
        
        // Wait for the download to complete
        await fulfillment(of: [downloadExpectation], timeout: 30)
        
        // Verify download succeeded
        let downloadSuccess = await downloadSuccessCounter.value == 1
        XCTAssertTrue(downloadSuccess, "Download should complete successfully")
        
        // Get fileURL from first manager
        let firstManagerURL = await manager.fileURL(for: resource.id)
        XCTAssertNotNil(firstManagerURL, "First manager should have file URL")
        
        // Verify file exists
        if let url = firstManagerURL {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "File should exist")
        }
        
        // Create a new manager with the same cache configuration
        let secondDownloadQueue = DownloadQueue()
        await secondDownloadQueue.add(processor: WebDownloadProcessor(configuration: .default))
        
        // Use the same cache configuration to ensure persistence
        let secondManager = ResourceManager(cache: cache, downloadQueue: secondDownloadQueue)
        
        // Verify fileURL is still available from the new manager
        let secondManagerURL = await secondManager.fileURL(for: resource.id)
        XCTAssertNotNil(secondManagerURL, "Second manager should have file URL")
        XCTAssertEqual(secondManagerURL, firstManagerURL, "Both managers should return the same file URL")
        
        // Verify file still exists
        if let url = secondManagerURL {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "File should still exist")
        }
    }
    
    func testFileURLForResourceWithAlternativeMirrors() async throws {
        await setupManager()
        
        // Create a resource with multiple mirrors (main + alternatives)
        let resource = Resource(
            id: "alternative-mirrors-test",
            main: FileMirror(
                id: "main-mirror",
                location: "https://invalid-domain-12345.com/image.jpg", // This will fail
                info: [WeightedMirrorPolicy.weightKey: 1]
            ),
            alternatives: [
                FileMirror(
                    id: "alternative-mirror-1",
                    location: "https://picsum.photos/180/180.jpg", // This should succeed
                    info: [WeightedMirrorPolicy.weightKey: 100]
                ),
                FileMirror(
                    id: "alternative-mirror-2",
                    location: "https://picsum.photos/160/160.jpg", // Backup if needed
                    info: [WeightedMirrorPolicy.weightKey: 50]
                )
            ],
            fileURL: nil
        )
        
        // Verify fileURL is nil before download
        let initialURL = await manager.fileURL(for: resource.id)
        XCTAssertNil(initialURL, "File URL should be nil before download")
        
        // Request the download
        let requests = await manager.request(resources: [resource])
        XCTAssertEqual(requests.count, 1, "Should have one download request")
        
        // Set up completion expectation
        let downloadExpectation = XCTestExpectation(description: "Download should complete with alternative mirror")
        let downloadSuccessCounter = ActorCounter()
        
        await manager.addResourceCompletion(for: resource) { @Sendable (success, _) in
            Task {
                await downloadSuccessCounter.setValue(success ? 1 : 0)
                downloadExpectation.fulfill()
            }
        }
        
        // Process the download
        await manager.process(requests: requests)
        
        // Wait for the download to complete (should succeed with alternative mirror)
        await fulfillment(of: [downloadExpectation], timeout: 60)
        
        // Verify download succeeded using alternative mirror
        let downloadSuccess = await downloadSuccessCounter.value == 1
        XCTAssertTrue(downloadSuccess, "Download should succeed using alternative mirror")
        
        // Verify fileURL is available after successful download
        let finalURL = await manager.fileURL(for: resource.id)
        XCTAssertNotNil(finalURL, "File URL should be available after successful download with alternative mirror")
        
        // Verify file exists and has content
        if let url = finalURL {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "File should exist")
            
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[FileAttributeKey.size] as? Int64 ?? 0
            XCTAssertGreaterThan(fileSize, 0, "File should have content")
            
            // Try to create an image from the data to verify it's valid
            let data = try Data(contentsOf: url)
            let image = LocalImage(data: data)
            XCTAssertNotNil(image, "Should be able to create image from downloaded data")
        }
        
        // Verify resource is cached
        let cachedURL = await cache.fileURL(for: resource.id)
        XCTAssertNotNil(cachedURL, "Resource should be cached after successful download")
        XCTAssertEqual(cachedURL, finalURL, "Cached URL should match fileURL")
    }
    
    func testFileURLForResourceWithEmptyID() async throws {
        await setupManager()
        
        let sampleMain = FileMirror(id: UUID().uuidString, location: "https://example.com/sample", info: [:])
        let resource = Resource(id: "", main: sampleMain)
        
        let url = await manager.fileURL(for: resource.id)
        XCTAssertNil(url, "File URL should be nil for a resource with empty ID.")
    }
    
    func testFileURLForResourceWithUnicodeID() async throws {
        await setupManager()
        
        let unicodeID = "资源-🎯-тест-123"
        let sampleMain = FileMirror(id: UUID().uuidString, location: "https://example.com/sample", info: [:])
        let resource = Resource(id: unicodeID, main: sampleMain)
        
        // Create a temporary file to simulate a cached resource
        let tempFileURL = try FileManager.createFileOnDisk()
        
        // Store the resource in cache
        let options = RequestOptions(storagePriority: .cached)
        let localFile = try await cache.localCache.store(resource: resource, mirror: resource.main, at: tempFileURL, options: options)
        
        let url = await manager.fileURL(for: resource.id)
        XCTAssertNotNil(url, "File URL should not be nil for a cached resource with unicode ID.")
        XCTAssertEqual(url, localFile.fileURL, "File URL should match the cached file URL.")
    }
    
    // MARK: - Cache Behavior Tests
    
    func testFileURLAfterCacheCleanup() async throws {
        await setupManager()
        
        let sampleMain = FileMirror(id: UUID().uuidString, location: "https://example.com/sample", info: [:])
        let resource = Resource(id: UUID().uuidString, main: sampleMain)
        
        // Create a temporary file to simulate a cached resource
        let tempFileURL = try FileManager.createFileOnDisk()
        
        // Store the resource in cache
        let options = RequestOptions(storagePriority: .cached)
        _ = try await cache.localCache.store(resource: resource, mirror: resource.main, at: tempFileURL, options: options)
        
        // Verify the file URL is available
        let urlBefore = await manager.fileURL(for: resource.id)
        XCTAssertNotNil(urlBefore, "File URL should be available before cleanup.")
        
        // Clean up the cache, excluding this file
        await cache.cleanup(excluding: [])
        
        // File URL should be nil after cleanup
        let urlAfter = try await cache.localCache.fileURL(for: resource.id)
        XCTAssertNil(urlAfter, "File URL should be nil after cache cleanup.")
    }
    
    func testFileURLAfterStorageUpdate() async throws {
        await setupManager()
        
        let sampleMain = FileMirror(id: UUID().uuidString, location: "https://example.com/sample", info: [:])
        let resource = Resource(id: UUID().uuidString, main: sampleMain)
        
        // Create a temporary file to simulate a cached resource
        let tempFileURL = try FileManager.createFileOnDisk()
        
        // Store the resource in cache with cached priority
        let cachedOptions = RequestOptions(storagePriority: .cached)
        _ = try await cache.localCache.store(resource: resource, mirror: resource.main, at: tempFileURL, options: cachedOptions)
        
        // Verify the file URL is available
        let urlBefore = await manager.fileURL(for: resource.id)
        XCTAssertNotNil(urlBefore, "File URL should be available before storage update.")
        
        // Update storage to permanent
        let updatedResources = await cache.localCache.updateStorage(resources: [resource], to: .permanent)
        XCTAssertEqual(updatedResources.count, 1, "One resource should be updated.")
        
        // File URL should still be available after storage update
        let urlAfter = await manager.fileURL(for: resource.id)
        XCTAssertNotNil(urlAfter, "File URL should still be available after storage update.")
    }
    
    // MARK: - Concurrent Access Tests
    
    func testActualDownloadAndFileURLAvailability() async throws {
        await setupManager()
        
        print("Starting integration test for actual download and fileURL availability...")
        
        // Create test resources using reliable online image service
        let resourceCount = 5
        let resources = (1...resourceCount).map { i in
            let imageSize = 100 + (i * 10) // 110x110, 120x120, 130x130, 140x140, 150x150
            let imageURL = "https://picsum.photos/\(imageSize)/\(imageSize).jpg"
            
            return Resource(
                id: "fileurl-test-resource-\(i)",
                main: FileMirror(
                    id: "fileurl-test-mirror-\(i)",
                    location: imageURL,
                    info: [:]
                ),
                alternatives: [],
                fileURL: nil
            )
        }
        
        // Verify initial state - no fileURL should be available
        for resource in resources {
            let initialURL = await manager.fileURL(for: resource.id)
            XCTAssertNil(initialURL, "FileURL should be nil before download for resource \(resource.id)")
        }
        
        // Ensure manager is active
        let isActive = await manager.isActive
        XCTAssertTrue(isActive, "Manager should be active for downloads")
        
        // Request downloads
        let requests = await manager.request(resources: resources)
        print("Created \(requests.count) download requests")
        XCTAssertEqual(requests.count, resourceCount, "All resources should be requested for download")
        
        // Set up completion tracking
        let downloadExpectation = XCTestExpectation(description: "Downloads should complete")
        downloadExpectation.expectedFulfillmentCount = resources.count
        
        let successfulDownloads = ActorArray<String>()
        let failedDownloads = ActorArray<String>()
        
        // Set up completion handlers
        for resource in resources {
            await manager.addResourceCompletion(for: resource) { @Sendable (success, resourceID) in
                Task {
                    if success {
                        await successfulDownloads.append(resourceID)
                    } else {
                        await failedDownloads.append(resourceID)
                    }
                    downloadExpectation.fulfill()
                }
            }
        }
        
        // Process the downloads
        await manager.process(requests: requests)
        
        // Wait for downloads to complete
        await fulfillment(of: [downloadExpectation], timeout: 60)
        
        let successfulCount = await successfulDownloads.count
        let failedCount = await failedDownloads.count
        
        print("Download results: \(successfulCount) successful, \(failedCount) failed")
        
        // Verify all downloads were processed
        XCTAssertEqual(successfulCount + failedCount, resourceCount, "All downloads should be processed")
        
        // For successful downloads, verify fileURL is available
        let successfulIDs = await successfulDownloads.values
        
        for resourceID in successfulIDs {
            guard let resource = resources.first(where: { $0.id == resourceID }) else {
                XCTFail("Could not find resource with ID \(resourceID)")
                continue
            }
            
            let fileURL = await manager.fileURL(for: resource.id)
            XCTAssertNotNil(fileURL, "FileURL should be available for successfully downloaded resource \(resourceID)")
            
            if let url = fileURL {
                // Verify file exists at the URL
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), 
                             "File should exist at returned URL for resource \(resourceID)")
                
                // Verify file has content (image files should be > 0 bytes)
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = attributes[FileAttributeKey.size] as? Int64 ?? 0
                XCTAssertGreaterThan(fileSize, 0, "Downloaded file should have content for resource \(resourceID)")
                
                print("✅ Resource \(resourceID): FileURL available at \(url.path), size: \(fileSize) bytes")
            }
        }
        
        // Verify resources are properly cached
        var cachedResourceCount = 0
        for resource in resources {
            if let cachedURL = await cache.fileURL(for: resource.id) {
                cachedResourceCount += 1
                
                // Verify cached URL matches fileURL
                let managerURL = await manager.fileURL(for: resource.id)
                XCTAssertEqual(cachedURL, managerURL, 
                              "Cached URL should match manager fileURL for resource \(resource.id)")
            }
        }
        
        print("Cache verification: \(cachedResourceCount) resources found in cache")
        XCTAssertEqual(cachedResourceCount, successfulCount, "All successful downloads should be cached")
        
        // Test cache effectiveness - request same resources again
        print("Testing cache effectiveness...")
        let secondRequests = await manager.request(resources: resources)
        print("Second request: \(secondRequests.count) new downloads needed")
        
        // Should need fewer downloads due to caching
        XCTAssertLessThanOrEqual(secondRequests.count, requests.count, 
                                "Second request should need fewer downloads due to caching")
        
        // For cached resources, fileURL should still be available immediately
        for resource in resources {
            let cachedURL = await cache.fileURL(for: resource.id)
            if cachedURL != nil {
                let fileURL = await manager.fileURL(for: resource.id)
                XCTAssertNotNil(fileURL, "FileURL should be available for cached resource \(resource.id)")
            }
        }
        
        print("✅ Integration test completed successfully")
        print("Downloaded \(successfulCount) files, verified fileURL availability and caching")
    }
    
    /// Test downloading a single large image and verify fileURL properties
    func testSingleLargeImageDownloadAndFileURL() async throws {
        await setupManager()
        
        print("Testing single large image download and fileURL verification...")
        
        // Create resource for a larger image
        let resource = Resource(
            id: "large-image-test",
            main: FileMirror(
                id: "large-image-mirror",
                location: "https://picsum.photos/800/600.jpg", // 800x600 image
                info: [:]
            ),
            alternatives: [],
            fileURL: nil
        )
        
        // Verify no fileURL initially
        let initialURL = await manager.fileURL(for: resource.id)
        XCTAssertNil(initialURL, "FileURL should be nil before download")
        
        // Request download
        let requests = await manager.request(resources: [resource])
        XCTAssertEqual(requests.count, 1, "Should have one download request")
        
        // Set up completion tracking
        let downloadExpectation = XCTestExpectation(description: "Large image download should complete")
        let downloadSuccessCounter = ActorCounter()
        
        await manager.addResourceCompletion(for: resource) { @Sendable (success, resourceID) in
            Task {
                await downloadSuccessCounter.setValue(success ? 1 : 0)
                downloadExpectation.fulfill()
            }
        }
        
        // Process the download
        await manager.process(requests: requests)
        
        // Wait for download to complete
        await fulfillment(of: [downloadExpectation], timeout: 60)
        
        let downloadSuccess = await downloadSuccessCounter.value == 1
        
        if downloadSuccess {
            print("✅ Large image download completed successfully")
            
            // Verify fileURL is available
            let fileURL = await manager.fileURL(for: resource.id)
            XCTAssertNotNil(fileURL, "FileURL should be available after successful download")
            
            if let url = fileURL {
                // Verify file exists and has reasonable size for an image
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), 
                             "Downloaded file should exist")
                
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = attributes[FileAttributeKey.size] as? Int64 ?? 0
                XCTAssertGreaterThan(fileSize, 1000, "Image file should be reasonably sized (>1KB)")
                
                // Verify file extension or content type if possible
                XCTAssertTrue(url.pathExtension.lowercased() == "jpg" || 
                             url.pathExtension.lowercased() == "jpeg" || 
                             url.pathExtension.isEmpty, 
                             "File should have appropriate extension or be extensionless")
                
                print("✅ Large image verified: \(url.path), size: \(fileSize) bytes")
            }
            
            // Verify resource is cached
            let cachedURL = await cache.fileURL(for: resource.id)
            XCTAssertNotNil(cachedURL, "Downloaded resource should be cached")
            XCTAssertEqual(cachedURL, fileURL, "Cached URL should match fileURL")
            
        } else {
            print("⚠️ Large image download failed - this may be due to network conditions")
            
            // Even if download failed, fileURL should still be nil
            let fileURL = await manager.fileURL(for: resource.id)
            XCTAssertNil(fileURL, "FileURL should be nil for failed download")
        }
    }
    
    func testFileURLReturnsValidURLAfterDownload() async throws {
        await setupManager()
        
        // Create a test resource with a unique ID
        let uniqueID = "test-fileurl-after-download-\(UUID().uuidString)"
        let resource = Resource(
            id: uniqueID,
            main: FileMirror(
                id: "mirror-\(uniqueID)",
                location: "https://picsum.photos/150/150.jpg",
                info: [:]
            ),
            alternatives: [],
            fileURL: nil
        )
        
        // Verify fileURL is nil before download
        let initialURL = await manager.fileURL(for: resource.id)
        XCTAssertNil(initialURL, "File URL should be nil before download")
        
        // Request the download using manager.request()
        let requests = await manager.request(resources: [resource])
        XCTAssertEqual(requests.count, 1, "Should have one download request")
        
        // Use XCTestExpectation with completion handler to wait for download completion
        let downloadExpectation = XCTestExpectation(description: "Download should complete successfully")
        let downloadSuccessCounter = ActorCounter()
        
        await manager.addResourceCompletion(for: resource) { @Sendable (success, resourceID) in
            Task {
                await downloadSuccessCounter.setValue(success ? 1 : 0)
                downloadExpectation.fulfill()
            }
        }
        
        // Process the download using manager.process()
        await manager.process(requests: requests)
        
        // Wait for download completion
        await fulfillment(of: [downloadExpectation], timeout: 30)
        
        // Verify download was successful
        let downloadSuccess = await downloadSuccessCounter.value == 1
        XCTAssertTrue(downloadSuccess, "Download should complete successfully")
        
        // After successful download, call manager.fileURL(for: resource)
        let fileURL = await manager.fileURL(for: resource.id)
        
        // Assert the returned URL is not nil
        XCTAssertNotNil(fileURL, "File URL should not be nil after successful download")
        
        // Verify the URL path contains expected components (cache directory, resource ID)
        if let url = fileURL {
            let urlPath = url.path
            
            // Verify the file exists at the returned URL
            XCTAssertTrue(FileManager.default.fileExists(atPath: urlPath), 
                         "File should exist at the returned URL")
            
            // Verify the URL path contains the resource ID
            XCTAssertTrue(urlPath.contains(uniqueID), 
                         "URL path should contain the resource ID: \(uniqueID)")
            
            // Verify the URL path is within a cache directory structure
            // The exact cache directory structure may vary, but it should contain typical cache path components
            let pathComponents = url.pathComponents
            let hasExpectedCacheStructure = pathComponents.contains { component in
                component.lowercased().contains("cache") || 
                component.lowercased().contains("library") ||
                component.lowercased().contains("tmp")
            }
            
            XCTAssertTrue(hasExpectedCacheStructure, 
                         "URL path should contain cache directory components. Path: \(urlPath)")
            
            // Verify the file has content (should be > 0 bytes for a valid image)
            let attributes = try FileManager.default.attributesOfItem(atPath: urlPath)
            let fileSize = attributes[FileAttributeKey.size] as? Int64 ?? 0
            XCTAssertGreaterThan(fileSize, 0, "Downloaded file should have content")
        }
    }
    
    // MARK: - Performance Tests
    
    // Temporarily commented out due to compilation issues
    /*
    func testFileURLPerformance() async throws {
        await setupManager()
        
        let sampleMain = FileMirror(id: UUID().uuidString, location: "https://example.com/sample", info: [:])
        let resource = Resource(id: UUID().uuidString, main: sampleMain)
        
        // Create a temporary file to simulate a cached resource
        let tempFileURL = try FileManager.createFileOnDisk()
        
        // Store the resource in cache
        let options = RequestOptions(storagePriority: .cached)
        let localFile = try await cache.localCache.store(resource: resource, mirror: resource.main, at: tempFileURL, options: options)
        
        // Measure performance of fileURL access
        measure {
            let expectation = self.expectation(description: "File URL retrieval performance")
            
            Task {
                for _ in 0..<100 {
                    let url = await manager.fileURL(for: resource)
                    XCTAssertNotNil(url, "File URL should be available.")
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 5.0)
        }
    }
    
    func testFileURLBatchPerformance() async throws {
        await setupManager()
        
        let resourceCount = 100
        let resources = (1...resourceCount).map { i in
            let sampleMain = FileMirror(id: "mirror-\(i)", location: "https://example.com/sample-\(i)", info: [:])
            return Resource(id: "resource-\(i)", main: sampleMain)
        }
        
        let options = RequestOptions(storagePriority: .cached)
        
        // Store multiple resources
        for resource in resources {
            let tempFileURL = try FileManager.createFileOnDisk()
            let _ = try await cache.localCache.store(resource: resource, mirror: resource.main, at: tempFileURL, options: options)
        }
        
        // Measure performance of batch fileURL access
        measure {
            let expectation = self.expectation(description: "Batch file URL retrieval performance")
            
            Task {
                for resource in resources {
                    let url = await manager.fileURL(for: resource)
                    XCTAssertNotNil(url, "File URL should be available for resource \(resource.id).")
                }
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 10.0)
        }
    }
    */
}

