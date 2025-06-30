import XCTest
import RealmSwift
@testable import DownloadKit

class LocalCacheManagerTests: XCTestCase {
    
    /// In memory realm configuration.
    let config = Realm.Configuration(inMemoryIdentifier: "memory-id")
    let cachedOptions = RequestOptions(downloadPriority: .normal, storagePriority: .cached)
    let permanentOptions = RequestOptions(downloadPriority: .normal, storagePriority: .permanent)
    
    var manager: RealmLocalCacheManager<CachedLocalFile>!
    
    var url: URL {
        return try! FileManager.createFileOnDisk()
    }
    
    override func setUpWithError() throws {
        manager = RealmLocalCacheManager<CachedLocalFile>(configuration: config)
    }

    override func tearDownWithError() throws {
        try manager.cleanup(excluding: [])
        manager = nil
    }
    
    func testStoringResourceFile() throws {
        let resource = Resource(id: UUID().uuidString, main: ())
        
        let stored = try manager.store(resource: resource, mirror: resource.main, at: url, options: cachedOptions)
        
        XCTAssertNotNil(stored, "Local resource was stored in realm.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.fileURL!.path))
    }
    
    func testRequestingDownloadsOnEmptyCacheReturnsAllResources() {
        let resources: [Resource] = (0..<5).map({ _ in Resource(id: UUID().uuidString) })
        let requests = manager.downloads(from: resources, options: cachedOptions)
        
        XCTAssertEqual(5, requests.count, "Manager should return 5 resources that need to be downloaded.")
    }
    
    func testRequestingDownloadsReturnsCorrectResources() throws {
        let resources: [Resource] = (0..<5).map({ _ in Resource(id: UUID().uuidString) })
        
        // store first resource
        let first = resources.first!
        let _ = try manager.store(resource: first, mirror: first.main, at: url, options: cachedOptions)
        
        // request downloads should only return 4 resources since the first one is saved
        let requests = manager.downloads(from: resources, options: cachedOptions)
        
        XCTAssertEqual(4, requests.count, "Manager should return only 4 resources that need to be downloaded.")
    }
    
    func testUpdatingStorage() throws {
        let resources: [Resource] = (0..<5).map({ _ in Resource(id: UUID().uuidString) })
        
        // store to realm
        for resource in resources {
            let _ = try manager.store(resource: resource, mirror: resource.main, at: url, options: cachedOptions)
        }
        
        // update stored resources and move them to permanent storage
        manager.updateStorage(assets: resources, to: .permanent, onAssetChange: nil)
        
        let requests = manager.downloads(from: resources, options: permanentOptions)
        XCTAssertEqual(requests.count, 0, "All resources should be stored locally in permanent storage")
    }
    
    func testResetingLocalCache() throws {
        let resources: [Resource] = (0..<5).map({ _ in Resource(id: UUID().uuidString) })
        
        // store to realm
        for resource in resources {
            let _ = try manager.store(resource: resource, mirror: resource.main, at: url, options: cachedOptions)
        }
        
        // reset local cache
        try manager.reset()
        
        let requests = manager.downloads(from: resources, options: permanentOptions)
        XCTAssertEqual(requests.count, 5, "Manager should return 5 requests, since everything was removed.")
    }
    
    func testCleanup() throws {
        let resources: [Resource] = (0..<5).map({ _ in Resource(id: UUID().uuidString) })
        
        // store to realm
        let localResources = resources.map { resource in
            return try! manager.store(resource: resource, mirror: resource.main, at: url, options: permanentOptions)
        }
        
        // clean up everything except the first resource
        try manager.cleanup(excluding: Set([localResources.first!.fileURL!]))
        let requested = manager.downloads(from: resources, options: permanentOptions)
        
        XCTAssertEqual(requested.count, 4)
    }
    
}

extension FileManager {
    var supportDirectoryURL: URL {
        return self.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
    
    var cacheDirectoryURL: URL {
        return self.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }
    
    static func createFileOnDisk() throws -> URL {
        let filename = FileManager.default.cacheDirectoryURL.appendingPathComponent(UUID().uuidString)

        // we're just outputting an emoji into a file
        try "😃".write(to: filename, atomically: true, encoding: String.Encoding.utf8)
        
        return filename
    }
}

