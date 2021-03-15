import XCTest
import RealmSwift
@testable import DownloadKit

class AssetManagerTests: XCTestCase {
    
    var manager: AssetManager!
    var cache: RealmCacheManager<LocalFile>!
    
    var assets: [Asset] {
        let assets = [
            Asset(id: "asset-id",
                  main: FileMirror(id: "asset-id", location: "https://picsum.photos/10", info: [:]),
                  alternatives: [
                    FileMirror(id: "asset-id", location: "https://picsum.photos/100", info: [WeightedMirrorPolicy.weightKey: 100]),
                    FileMirror(id: "asset-id", location: "https://picsum.photos/50", info: [WeightedMirrorPolicy.weightKey: 50])
                  ],
                  fileURL: nil)
        ]
        
        return assets
    }
    
    override func setUpWithError() throws {
        let downloadQueue = DownloadQueue()
        downloadQueue.add(processor: WebDownloadProcessor(configuration: .ephemeral))
        
        // Uses weighted mirror policy by default
        cache = RealmCacheManager<LocalFile>()
        manager = AssetManager(cache: cache, downloadQueue: downloadQueue)
    }
    
    func setupWithPriorityQueue() {
        let downloadQueue = DownloadQueue()
        downloadQueue.add(processor: WebDownloadProcessor(configuration: .ephemeral))
        
        let priorityQueue = DownloadQueue()
        priorityQueue.add(processor: WebDownloadProcessor.priorityProcessor())
        priorityQueue.simultaneousDownloads = 10
        
        // Uses weighted mirror policy by default
        cache = RealmCacheManager<LocalFile>()
        manager = AssetManager(cache: cache, downloadQueue: downloadQueue, priorityQueue: priorityQueue)
    }

    override func tearDownWithError() throws {
        cache = nil
        manager = nil
    }
    
    func testRequestingEmptyArray() throws {
        let requests = manager.request(assets: [])
        XCTAssertEqual(requests.count, 0)
    }
    
    func testRequestingDownloads() throws {
        let requests = manager.request(assets: assets)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.identifier, "asset-id", "First downloadable should be the mirror with highest weight")
    }
    
    func testRequestingDownloadsWithPriorityQueue() throws {
        setupWithPriorityQueue()
        
        let requests = manager.request(assets: assets)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.identifier, "asset-id", "First downloadable should be the mirror with highest weight")
    }
    
    func testAssetCompletionIsCalled() throws {
        let expectation = XCTestExpectation(description: "Requesting downloads should call completion.")
        
        manager.request(assets: assets)
        manager.addAssetCompletion(for: "asset-id") { (success, assetID) in
            XCTAssertTrue(success)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5)
    }

}
