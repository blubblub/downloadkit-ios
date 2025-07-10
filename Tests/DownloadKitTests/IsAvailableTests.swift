//
//  IsAvailableTests.swift
//  DownloadKitTests
//
//  Created by Assistant on 2025-07-09.
//

import XCTest
import RealmSwift
@testable import DownloadKit
@testable import DownloadKitRealm

/// Unit tests for the isAvailable method in RealmCacheManager
class IsAvailableTests: XCTestCase {
    
    var cache: RealmCacheManager<CachedLocalFile>!
    var localCache: RealmLocalCacheManager<CachedLocalFile>!
    var realm: Realm!
    
    override func setUpWithError() throws {
        // Synchronous setup - realm will be configured in async test methods
    }
    
    override func tearDownWithError() throws {
        // Clear references - in-memory realm will be automatically cleaned up
        cache = nil
        localCache = nil
        realm = nil
    }
    
    /// Helper method to setup cache manager with in-memory realm
    private func setupCache() async {
        let config = Realm.Configuration(inMemoryIdentifier: "is-available-test-\(UUID().uuidString)")
        
        // Create Realm instance and keep it alive during the test
        realm = try! await Realm(configuration: config, actor: MainActor.shared)
        
        localCache = RealmLocalCacheManager<CachedLocalFile>(configuration: config)
        cache = RealmCacheManager<CachedLocalFile>(configuration: config)
    }
    
    /// Creates a test resource for testing
    private func createTestResource(id: String) -> Resource {
        return Resource(
            id: id,
            main: FileMirror(
                id: "mirror-\(id)",
                location: "https://example.com/test.jpg",
                info: [:]
            ),
            alternatives: [],
            fileURL: nil
        )
    }
    
    /// Creates a temporary file for testing
    private func createTemporaryFile() throws -> URL {
        let filename = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        // Create a simple test file
        try "test content".write(to: filename, atomically: true, encoding: .utf8)
        
        return filename
    }
    
    // MARK: - Test Cases
    
    /// Test that isAvailable returns false for a resource that doesn't exist in cache
    func testIsAvailable_ResourceNotInCache_ReturnsFalse() async throws {
        await setupCache()
        
        let resource = createTestResource(id: "non-existent-resource")
        
        let isAvailable = await cache.isAvailable(resource: resource)
        
        XCTAssertFalse(isAvailable, "Resource should not be available when not in cache")
    }
    
    /// Test that isAvailable returns true for a resource that exists in cache
    func testIsAvailable_ResourceInCache_ReturnsTrue() async throws {
        await setupCache()
        
        let resource = createTestResource(id: "cached-resource")
        let tempFile = try createTemporaryFile()
        
        // Store the resource in cache
        let cachedOptions = RequestOptions(storagePriority: .cached)
        let _ = try localCache.store(resource: resource, mirror: resource.main, at: tempFile, options: cachedOptions)
        
        let isAvailable = await cache.isAvailable(resource: resource)
        
        XCTAssertTrue(isAvailable, "Resource should be available when stored in cache")
    }
    
    /// Test that isAvailable returns false for a resource that exists in database but file is missing
    func testIsAvailable_ResourceInDatabaseButFileMissing_ReturnsFalse() async throws {
        await setupCache()
        
        let resource = createTestResource(id: "missing-file-resource")
        let tempFile = try createTemporaryFile()
        
        // Store the resource in cache
        let cachedOptions = RequestOptions(storagePriority: .cached)
        let localResource = try localCache.store(resource: resource, mirror: resource.main, at: tempFile, options: cachedOptions)
        
        // Verify it's available before deletion
        let isAvailableBeforeDelete = await cache.isAvailable(resource: resource)
        XCTAssertTrue(isAvailableBeforeDelete, "Resource should be available before file deletion")
        
        // Delete the actual file from disk
        if let fileURL = localResource.fileURL {
            try FileManager.default.removeItem(at: fileURL)
        }
        
        // Trigger cleanup by calling requestDownloads which will remove orphaned database entries
        let _ = await cache.requestDownloads(resources: [resource], options: cachedOptions)
        
        let isAvailable = await cache.isAvailable(resource: resource)
        
        XCTAssertFalse(isAvailable, "Resource should not be available when file is missing from disk")
    }
    
    /// Test that isAvailable works correctly with multiple resources
    func testIsAvailable_MultipleResources_ReturnsCorrectAvailability() async throws {
        await setupCache()
        
        let cachedResource = createTestResource(id: "cached-resource")
        let uncachedResource = createTestResource(id: "uncached-resource")
        
        // Store only one resource in cache
        let tempFile = try createTemporaryFile()
        let cachedOptions = RequestOptions(storagePriority: .cached)
        let _ = try localCache.store(resource: cachedResource, mirror: cachedResource.main, at: tempFile, options: cachedOptions)
        
        let cachedIsAvailable = await cache.isAvailable(resource: cachedResource)
        let uncachedIsAvailable = await cache.isAvailable(resource: uncachedResource)
        
        XCTAssertTrue(cachedIsAvailable, "Cached resource should be available")
        XCTAssertFalse(uncachedIsAvailable, "Uncached resource should not be available")
    }
    
    /// Test that isAvailable works correctly with different storage priorities
    func testIsAvailable_DifferentStoragePriorities_ReturnsTrue() async throws {
        await setupCache()
        
        let cachedResource = createTestResource(id: "cached-resource")
        let permanentResource = createTestResource(id: "permanent-resource")
        
        // Store resources with different storage priorities
        let tempFile1 = try createTemporaryFile()
        let tempFile2 = try createTemporaryFile()
        
        let cachedOptions = RequestOptions(storagePriority: .cached)
        let permanentOptions = RequestOptions(storagePriority: .permanent)
        
        let _ = try localCache.store(resource: cachedResource, mirror: cachedResource.main, at: tempFile1, options: cachedOptions)
        let _ = try localCache.store(resource: permanentResource, mirror: permanentResource.main, at: tempFile2, options: permanentOptions)
        
        let cachedIsAvailable = await cache.isAvailable(resource: cachedResource)
        let permanentIsAvailable = await cache.isAvailable(resource: permanentResource)
        
        XCTAssertTrue(cachedIsAvailable, "Cached resource should be available")
        XCTAssertTrue(permanentIsAvailable, "Permanent resource should be available")
    }
    
    /// Test that isAvailable works correctly with resource modification dates
    func testIsAvailable_ResourceWithModificationDate_ReturnsCorrectAvailability() async throws {
        await setupCache()
        
        let oldDate = Date(timeIntervalSinceNow: -3600) // 1 hour ago
        let newDate = Date(timeIntervalSinceNow: -1800) // 30 minutes ago
        
        // Create resource with old modification date
        let oldResource = Resource(
            id: "dated-resource",
            main: FileMirror(
                id: "mirror-dated-resource",
                location: "https://example.com/test.jpg",
                info: [:]
            ),
            alternatives: [],
            fileURL: nil,
            modifyDate: oldDate
        )
        
        // Store the resource in cache
        let tempFile = try createTemporaryFile()
        let cachedOptions = RequestOptions(storagePriority: .cached)
        let _ = try localCache.store(resource: oldResource, mirror: oldResource.main, at: tempFile, options: cachedOptions)
        
        // Check availability with same modification date
        let isAvailableOld = await cache.isAvailable(resource: oldResource)
        XCTAssertTrue(isAvailableOld, "Resource with same modification date should be available")
        
        // Create resource with newer modification date
        let newResource = Resource(
            id: "dated-resource", // Same ID
            main: FileMirror(
                id: "mirror-dated-resource",
                location: "https://example.com/test.jpg",
                info: [:]
            ),
            alternatives: [],
            fileURL: nil,
            modifyDate: newDate
        )
        
        // Check availability with newer modification date
        let isAvailableNew = await cache.isAvailable(resource: newResource)
        XCTAssertFalse(isAvailableNew, "Resource with newer modification date should not be available (needs re-download)")
    }
    
    /// Test that isAvailable works correctly after cache reset
    func testIsAvailable_AfterCacheReset_ReturnsFalse() async throws {
        await setupCache()
        
        let resource = createTestResource(id: "reset-test-resource")
        let tempFile = try createTemporaryFile()
        
        // Store the resource in cache
        let cachedOptions = RequestOptions(storagePriority: .cached)
        let _ = try localCache.store(resource: resource, mirror: resource.main, at: tempFile, options: cachedOptions)
        
        // Verify resource is available before reset
        let isAvailableBeforeReset = await cache.isAvailable(resource: resource)
        XCTAssertTrue(isAvailableBeforeReset, "Resource should be available before reset")
        
        // Reset the cache
        try localCache.reset()
        
        // Verify resource is not available after reset
        let isAvailableAfterReset = await cache.isAvailable(resource: resource)
        XCTAssertFalse(isAvailableAfterReset, "Resource should not be available after reset")
    }
    
    /// Test that isAvailable works correctly with ResourceFile extension
    func testIsAvailable_ResourceFileExtension_ReturnsCorrectAvailability() async throws {
        await setupCache()
        
        let resource = createTestResource(id: "extension-test-resource")
        let tempFile = try createTemporaryFile()
        
        // Store the resource in cache
        let cachedOptions = RequestOptions(storagePriority: .cached)
        let _ = try localCache.store(resource: resource, mirror: resource.main, at: tempFile, options: cachedOptions)
        
        // Test using the ResourceFile extension
        let isAvailable = await resource.isAvailable(in: cache)
        
        XCTAssertTrue(isAvailable, "Resource should be available when using ResourceFile extension")
    }
    
    /// Test performance of isAvailable with multiple resources
    func testIsAvailable_Performance_MultipleResources() async throws {
        await setupCache()
        
        // Create multiple resources
        let resourceCount = 100
        var resources: [Resource] = []
        
        for i in 0..<resourceCount {
            let resource = createTestResource(id: "performance-resource-\(i)")
            resources.append(resource)
            
            // Store every other resource to create a mix of available and unavailable
            if i % 2 == 0 {
                let tempFile = try createTemporaryFile()
                let cachedOptions = RequestOptions(storagePriority: .cached)
                let _ = try localCache.store(resource: resource, mirror: resource.main, at: tempFile, options: cachedOptions)
            }
        }
        
        // Measure performance
        let startTime = Date()
        
        var availableCount = 0
        for resource in resources {
            if await cache.isAvailable(resource: resource) {
                availableCount += 1
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        XCTAssertEqual(availableCount, resourceCount / 2, "Should have exactly half resources available")
        XCTAssertLessThan(duration, 1.0, "Performance test should complete within 1 second")
        
        print("Performance test: Checked \(resourceCount) resources in \(String(format: "%.3f", duration)) seconds")
        print("Average time per resource: \(String(format: "%.3f", duration / Double(resourceCount) * 1000)) ms")
    }
}
