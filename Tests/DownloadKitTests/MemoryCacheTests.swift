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
        let imageResult = await cache.resourceImage(url: URL(string: "https://google.com/logo.png")!)
        XCTAssertNil(imageResult)
        let subscriptResult = await cache["randomid"]
        XCTAssertNil(subscriptResult)
    }
    
    func testGettingImageFromCache() async {
        await setupCache()
        let imageURL = Bundle.module.url(forResource: "sample", withExtension: "png")!
        let imageResult1 = await cache.resourceImage(url: imageURL)
        XCTAssertNotNil(imageResult1)
        let imageResult2 = await cache.resourceImage(url: imageURL)
        XCTAssertNotNil(imageResult2)
    }
}
