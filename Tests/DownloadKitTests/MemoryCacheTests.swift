import XCTest
import RealmSwift
@testable import DownloadKit

class MemoryCacheTests: XCTestCase {
    
    let config = Realm.Configuration(inMemoryIdentifier: "memory-id")
    var cache: RealmMemoryCache<LocalFile>!
    
    override func setUpWithError() throws {
        cache = RealmMemoryCache<LocalFile>(configuration: config)
    }

    override func tearDownWithError() throws {
        cache = nil
    }
    
    func testFetchingFromEmptyCache() async {
        let imageResult = await cache.assetImage(url: URL(string: "https://google.com/logo.png")!)
        XCTAssertNil(imageResult)
        let subscriptResult = await cache["randomid"]
        XCTAssertNil(subscriptResult)
    }
    
    func testGettingImageFromCache() async {
        let imageURL = Bundle.module.url(forResource: "sample", withExtension: "png")!
        let imageResult1 = await cache.assetImage(url: imageURL)
        XCTAssertNotNil(imageResult1)
        let imageResult2 = await cache.assetImage(url: imageURL)
        XCTAssertNotNil(imageResult2)
    }
}
