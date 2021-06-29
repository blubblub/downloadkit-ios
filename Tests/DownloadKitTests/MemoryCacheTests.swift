import XCTest
import RealmSwift
@testable import DownloadKit

class MemoryCacheTests: XCTestCase {
    
    let config = Realm.Configuration(inMemoryIdentifier: "memory-id")
    var cache: RealmMemoryCache<LocalFile>!
    
    override func setUpWithError() throws {
        cache = RealmMemoryCache<LocalFile>(configuration: config, loadURLs: false)
    }

    override func tearDownWithError() throws {
        cache = nil
    }
    
    func testFetchingFromEmptyCache() {
        XCTAssertNil(cache.assetImage(url: URL(string: "https://google.com/logo.png")!))
        XCTAssertNil(cache["randomid"])
    }
    
    func testGettingImageFromCache() {
        let imageURL = Bundle.module.url(forResource: "sample", withExtension: "png")!
        XCTAssertNotNil(cache.assetImage(url: imageURL))
        XCTAssertNotNil(cache.assetImage(url: imageURL))
    }
}
