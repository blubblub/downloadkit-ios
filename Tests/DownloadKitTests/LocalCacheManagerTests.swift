import XCTest
import RealmSwift
@testable import DownloadKit

class LocalCacheManagerTests: XCTestCase {
    
    /// In memory realm configuration.
    let config = Realm.Configuration(inMemoryIdentifier: "local-cache-test-\(UUID().uuidString)")
    let cachedOptions = RequestOptions(storagePriority: .cached)
    let permanentOptions = RequestOptions(storagePriority: .permanent)
    
    var manager: RealmLocalCacheManager<CachedLocalFile>!
    var realm: Realm!
    
    var url: URL {
        return try! FileManager.createFileOnDisk()
    }
    
    override func setUpWithError() throws {
        // Synchronous setup - realm will be configured in async test methods
    }
    
    private func setupManager() async {
        // Create Realm instance and keep it alive during the test
        realm = try! await Realm(configuration: config, actor: MainActor.shared)
        manager = RealmLocalCacheManager<CachedLocalFile>(configuration: config)
    }

    override func tearDownWithError() throws {
        // Clear references - in-memory realm will be automatically cleaned up
        if let manager = manager {
            try manager.cleanup(excluding: [])
        }
        manager = nil
        realm = nil
    }
    
    func testStoringResourceFile() async throws {
        await setupManager()
        let sampleMain = FileMirror(id: UUID().uuidString, location: "https://example.com/sample", info: [:])
        let resource = Resource(id: UUID().uuidString, main: sampleMain)
        
        let stored = try manager.store(resource: resource, mirror: resource.main, at: url, options: cachedOptions)
        
        XCTAssertNotNil(stored, "Local resource was stored in realm.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.fileURL.path))
    }
    
    func testRequestingDownloadsOnEmptyCacheReturnsAllResources() async {
        await setupManager()
        let resources: [Resource] = (0..<5).map({ _ in
            let sampleMain = FileMirror(id: UUID().uuidString, location: "https://example.com/sample", info: [:])
            return Resource(id: UUID().uuidString, main: sampleMain)
        })
        let requests = manager.downloads(from: resources, options: cachedOptions)
        
        XCTAssertEqual(5, requests.count, "Manager should return 5 resources that need to be downloaded.")
    }
    
    func testRequestingDownloadsReturnsCorrectResources() async throws {
        await setupManager()
        let resources: [Resource] = (0..<5).map({ _ in
            let sampleMain = FileMirror(id: UUID().uuidString, location: "https://example.com/sample", info: [:])
            return Resource(id: UUID().uuidString, main: sampleMain)
        })
        
        // store first resource
        let first = resources.first!
        let _ = try manager.store(resource: first, mirror: first.main, at: url, options: cachedOptions)
        
        // request downloads should only return 4 resources since the first one is saved
        let requests = manager.downloads(from: resources, options: cachedOptions)
        
        XCTAssertEqual(4, requests.count, "Manager should return only 4 resources that need to be downloaded.")
    }
    
    func testUpdatingStorage() async throws {
        await setupManager()
        let resources: [Resource] = (0..<5).map({ _ in
            let sampleMain = FileMirror(id: UUID().uuidString, location: "https://example.com/sample", info: [:])
            return Resource(id: UUID().uuidString, main: sampleMain)
        })
        
        // store to realm
        for resource in resources {
            let _ = try manager.store(resource: resource, mirror: resource.main, at: url, options: cachedOptions)
        }
        
        // update stored resources and move them to permanent storage
        let _ = manager.updateStorage(resources: resources, to: .permanent)
        
        let requests = manager.downloads(from: resources, options: permanentOptions)
        XCTAssertEqual(requests.count, 0, "All resources should be stored locally in permanent storage")
    }
    
    func testResetingLocalCache() async throws {
        await setupManager()
        let resources: [Resource] = (0..<5).map({ _ in
            let sampleMain = FileMirror(id: UUID().uuidString, location: "https://example.com/sample", info: [:])
            return Resource(id: UUID().uuidString, main: sampleMain)
        })
        
        // store to realm
        for resource in resources {
            let _ = try manager.store(resource: resource, mirror: resource.main, at: url, options: cachedOptions)
        }
        
        // reset local cache
        try manager.reset()
        
        let requests = manager.downloads(from: resources, options: permanentOptions)
        XCTAssertEqual(requests.count, 5, "Manager should return 5 requests, since everything was removed.")
    }
    
    func testCleanup() async throws {
        await setupManager()
        let resources: [Resource] = (0..<5).map({ _ in
            let sampleMain = FileMirror(id: UUID().uuidString, location: "https://example.com/sample", info: [:])
            return Resource(id: UUID().uuidString, main: sampleMain)
        })
        
        // store to realm
        let localResources = resources.map { resource in
            return try! manager.store(resource: resource, mirror: resource.main, at: url, options: permanentOptions)
        }
        
        // clean up everything except the first resource
        try manager.cleanup(excluding: Set([localResources.first!.fileURL]))
        let requested = manager.downloads(from: resources, options: permanentOptions)
        
        XCTAssertEqual(requested.count, 4)
    }
    
}


