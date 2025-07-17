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
    
    override func tearDownWithError() throws {
        // Clear references - in-memory realm will be automatically cleaned up
        cache = nil
        manager = nil
        realm = nil
    }
    
    // MARK: - Basic fileURL Tests
    
    func testFileURLForResourceNotInCache() async throws {
        await setupManager()
        
        let sampleMain = FileMirror(id: UUID().uuidString, location: "https://example.com/sample", info: [:])
        let resource = Resource(id: UUID().uuidString, main: sampleMain)

        // No file should be cached, so the fileURL should be nil
        let url = await manager.fileURL(for: resource)
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
        
        let url = await manager.fileURL(for: resource)
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
        
        let url = await manager.fileURL(for: resource)
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
            let url = await manager.fileURL(for: resource)
            XCTAssertNotNil(url, "File URL should not be nil for cached resource \(resource.id).")
            XCTAssertEqual(url, storedURLs[index], "File URL should match the stored URL for resource \(resource.id).")
        }
    }
    
    // MARK: - Edge Cases Tests
    
    func testFileURLForResourceWithEmptyID() async throws {
        await setupManager()
        
        let sampleMain = FileMirror(id: UUID().uuidString, location: "https://example.com/sample", info: [:])
        let resource = Resource(id: "", main: sampleMain)
        
        let url = await manager.fileURL(for: resource)
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
        
        let url = await manager.fileURL(for: resource)
        XCTAssertNotNil(url, "File URL should not be nil for a cached resource with unicode ID.")
        XCTAssertEqual(url, localFile.fileURL, "File URL should match the cached file URL.")
    }
    
    func testFileURLForResourceWithLongID() async throws {
        await setupManager()
        
        let longID = String(repeating: "a", count: 1000)
        let sampleMain = FileMirror(id: UUID().uuidString, location: "https://example.com/sample", info: [:])
        let resource = Resource(id: longID, main: sampleMain)
        
        // Create a temporary file to simulate a cached resource
        let tempFileURL = try FileManager.createFileOnDisk()
        
        // Store the resource in cache
        let options = RequestOptions(storagePriority: .cached)
        let localFile = try await cache.localCache.store(resource: resource, mirror: resource.main, at: tempFileURL, options: options)
        
        let url = await manager.fileURL(for: resource)
        XCTAssertNotNil(url, "File URL should not be nil for a cached resource with long ID.")
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
        let localFile = try await cache.localCache.store(resource: resource, mirror: resource.main, at: tempFileURL, options: options)
        
        // Verify the file URL is available
        let urlBefore = await manager.fileURL(for: resource)
        XCTAssertNotNil(urlBefore, "File URL should be available before cleanup.")
        
        // Clean up the cache, excluding this file
        await cache.cleanup(excluding: [])
        
        // File URL should be nil after cleanup
        let urlAfter = await manager.fileURL(for: resource)
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
        let localFile = try await cache.localCache.store(resource: resource, mirror: resource.main, at: tempFileURL, options: cachedOptions)
        
        // Verify the file URL is available
        let urlBefore = await manager.fileURL(for: resource)
        XCTAssertNotNil(urlBefore, "File URL should be available before storage update.")
        
        // Update storage to permanent
        let updatedResources = await cache.localCache.updateStorage(resources: [resource], to: .permanent)
        XCTAssertEqual(updatedResources.count, 1, "One resource should be updated.")
        
        // File URL should still be available after storage update
        let urlAfter = await manager.fileURL(for: resource)
        XCTAssertNotNil(urlAfter, "File URL should still be available after storage update.")
    }
    
    // MARK: - Concurrent Access Tests
    
    func testFileURLConcurrentAccess() async throws {
        await setupManager()
        
        let sampleMain = FileMirror(id: UUID().uuidString, location: "https://example.com/sample", info: [:])
        let resource = Resource(id: UUID().uuidString, main: sampleMain)
        
        // Create a temporary file to simulate a cached resource
        let tempFileURL = try FileManager.createFileOnDisk()
        
        // Store the resource in cache
        let options = RequestOptions(storagePriority: .cached)
        let localFile = try await cache.localCache.store(resource: resource, mirror: resource.main, at: tempFileURL, options: options)
        
        // Create multiple concurrent tasks to access the file URL
        let concurrentTasks = (0..<10).map { _ in
            Task {
                return await manager.fileURL(for: resource)
            }
        }
        
        // Wait for all tasks to complete
        let results = await withTaskGroup(of: URL?.self) { group in
            for task in concurrentTasks {
                group.addTask { await task.value }
            }
            
            var urls: [URL?] = []
            for await result in group {
                urls.append(result)
            }
            return urls
        }
        
        // Verify all tasks returned the same URL
        for url in results {
            XCTAssertNotNil(url, "File URL should be available for concurrent access.")
            XCTAssertEqual(url, localFile.fileURL, "All concurrent accesses should return the same URL.")
        }
    }
    
    // MARK: - Performance Tests
    
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
}

// MARK: - Test Utilities

extension FileManager {
    var supportDirectoryURL: URL {
        return self.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
    
    var cacheDirectoryURL: URL {
        return self.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }
    
    static func createFileOnDisk() throws -> URL {
        let filename = FileManager.default.cacheDirectoryURL.appendingPathComponent(UUID().uuidString)

        // Create a small test file with emoji content
        try "😃".write(to: filename, atomically: true, encoding: String.Encoding.utf8)
        
        return filename
    }
}
