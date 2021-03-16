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
        XCTAssertEqual(manager.isActive, true)
        XCTAssertEqual(manager.currentDownloadCount, 0, "Manager should be empty.")
        XCTAssertEqual(manager.queuedDownloadCount, 0, "Manager should be empty.")
        XCTAssertEqual(manager.downloads.count, 0, "Manager should be empty.")
        XCTAssertEqual(manager.currentDownloads.count, 0, "Manager should be empty.")
        XCTAssertEqual(manager.queuedDownloads.count, 0, "Manager should be empty.")
        XCTAssertEqual(manager.hasItem(with: "random-id"), false, "Manager should be empty.")
        XCTAssertNil(manager.item(for: "random-id"), "Manager should be empty.")
        XCTAssertEqual(manager.isDownloading(for: "random-id"), false, "Manager should be empty.")
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
    
    func testThatMultipleAssetCompletionAreCalled() throws {
        let expectation = self.expectation(description: "Requesting downloads should call completion.")
        expectation.expectedFulfillmentCount = 2
        
        var callCount = 0
        manager.request(assets: assets)
        manager.addAssetCompletion(for: "asset-id") { (success, assetID) in
            callCount += 1
            expectation.fulfill()
        }
        
        manager.addAssetCompletion(for: "asset-id") { (success, assetID) in
            callCount += 1
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5) { (error) in
            XCTAssertEqual(callCount, 2, "Asset completion should be called two times")
        }
    }
    
    func testThatAddingAssetCompletionBeforeRequestingDownloadsFails() throws {
        let expectation = self.expectation(description: "Asset completion should be called immediately.")

        manager.addAssetCompletion(for: "asset-id") { (success, assetID) in
            XCTAssertFalse(success)
            expectation.fulfill()
        }
        
        manager.request(assets: assets)

        wait(for: [expectation], timeout: 2)
    }
    
    func testThatErrorHandlerIsCalled() {
        let expectation = self.expectation(description: "Requesting downloads should call completion.")
        
        let asset = Asset(id: "invalid-asset", main: FileMirror(id: "invalid-asset",
                                                                location: "http://invalid.url/jpg",
                                                                info: [:]),
                          alternatives: [],
                          fileURL: nil)
        manager.request(assets: [asset])
        manager.addAssetCompletion(for: "invalid-asset") { (success, assetID) in
            XCTAssertFalse(success)
            XCTAssertEqual("invalid-asset", assetID)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5)
    }
    
    func testCancelingAllDownloads() {
        let expectation = self.expectation(description: "Canceling all downloads should call completion.")
        
        manager.request(assets: assets)
        manager.addAssetCompletion(for: "asset-id") { (success, assetID) in
            XCTAssertFalse(success)
            XCTAssertEqual("asset-id", assetID)
            expectation.fulfill()
        }
        manager.cancelAll()
        
        wait(for: [expectation], timeout: 1)
    }
    
    func testMakingManagerInactive() {
        let expectation = self.expectation(description: "Completion should not be called.")
        expectation.isInverted = true // we don't want the expectation to be fulfilled
        
        manager.isActive = false
        let requests = manager.request(assets: assets)
        manager.addAssetCompletion(for: "asset-id") { (success, assetID) in
            expectation.fulfill()
        }
        
        // one request will be returned, but will never start executing
        XCTAssertEqual(requests.count, 1)
        
        wait(for: [expectation], timeout: 3)
    }
    
    func testMakingManagerActiveResumesDownloads() {
        let expectation = self.expectation(description: "Completion should not be called.")
        
        manager.isActive = false
        let requests = manager.request(assets: assets)
        manager.addAssetCompletion(for: "asset-id") { (success, assetID) in
            XCTAssertTrue(success)
            expectation.fulfill()
        }
        
        manager.resume()
        
        // one request will be returned, but will never start executing
        XCTAssertEqual(requests.count, 1)
        
        wait(for: [expectation], timeout: 3)
    }

}
