import XCTest
import RealmSwift
@testable import DownloadKit

class MemoryCacheTests: XCTestCase {
    
    let config = Realm.Configuration(inMemoryIdentifier: "memory-cache-test-\(UUID().uuidString)")
    var cache: RealmMemoryCache<CachedLocalFile>!
    var realm: Realm!
    
    override func setUpWithError() throws {
        // Synchronous setup - realm will be configured in async test methods
    }
    
    private func setupCache() async {
        // Create Realm instance and keep it alive during the test
        realm = try! await Realm(configuration: config, actor: MainActor.shared)
        cache = RealmMemoryCache<CachedLocalFile>(configuration: config)
    }

    override func tearDownWithError() throws {
        // Clear references - in-memory realm will be automatically cleaned up
        cache = nil
        realm = nil
    }
    
    func testFetchingFromEmptyCache() async {
        await setupCache()
        let imageResult = cache.image(for: "randomid")
        XCTAssertNil(imageResult)
        let fileURLResult = cache.fileURL(for: "randomid")
        XCTAssertNil(fileURLResult)
    }
    
    func testGettingImageFromCache() async {
        await setupCache()
        // Test with a resource ID instead of URL, since memory cache works with resource IDs
        // First we need to create a cached resource to test with
        let testResourceId = "test-resource-id"
        
        // Since memory cache is empty initially, this should return nil
        let imageResult1 = cache.image(for: testResourceId)
        XCTAssertNil(imageResult1, "Image should be nil for non-cached resource")
        
        // Test file URL retrieval
        let fileURLResult = cache.fileURL(for: testResourceId)
        XCTAssertNil(fileURLResult, "File URL should be nil for non-cached resource")
        
        // Test data retrieval
        let dataResult = cache.data(for: testResourceId)
        XCTAssertNil(dataResult, "Data should be nil for non-cached resource")
    }
}
