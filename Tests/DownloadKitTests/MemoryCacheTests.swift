import XCTest
import RealmSwift
@testable import DownloadKit

class MemoryCacheTests: XCTestCase {
    
    let config = Realm.Configuration(inMemoryIdentifier: "memory-cache-test-\(UUID().uuidString)")
    var cache: RealmMemoryCache<CachedLocalFile>!
    
    override func setUpWithError() throws {
        cache = RealmMemoryCache<CachedLocalFile>(configuration: config)
    }

    override func tearDownWithError() throws {
        cache = nil
    }
    
    func testFetchingFromEmptyCache() async {
        let imageResult = await cache.resourceImage(url: URL(string: "https://google.com/logo.png")!)
        XCTAssertNil(imageResult)
        let subscriptResult = await cache["randomid"]
        XCTAssertNil(subscriptResult)
    }
    
    func testGettingImageFromCache() async {
        let imageURL = Bundle.module.url(forResource: "sample", withExtension: "png")!
        let imageResult1 = await cache.resourceImage(url: imageURL)
        XCTAssertNotNil(imageResult1)
        let imageResult2 = await cache.resourceImage(url: imageURL)
        XCTAssertNotNil(imageResult2)
    }
}
