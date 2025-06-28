import XCTest
import RealmSwift
@testable import DownloadKit

class AssetManagerTests: XCTestCase {
    
    var manager: ResourceManager!
    var cache: RealmCacheManager<LocalFile>!
    
    var resources: [Asset] {
        let resources = [
            Asset(id: "asset-id",
                  main: FileMirror(id: "asset-id", location: "https://picsum.photos/10", info: [:]),
                  alternatives: [
                    FileMirror(id: "asset-id", location: "https://picsum.photos/100", info: [WeightedMirrorPolicy.weightKey: 100]),
                    FileMirror(id: "asset-id", location: "https://picsum.photos/50", info: [WeightedMirrorPolicy.weightKey: 50])
                  ],
                  fileURL: nil)
        ]
        
        return resources
    }
    
    override func setUpWithError() throws {
        let downloadQueue = DownloadQueue()
        Task {
            await downloadQueue.add(processor: WebDownloadProcessor(configuration: .ephemeral))
        }
        
        // Uses weighted mirror policy by default
        cache = RealmCacheManager<LocalFile>(configuration: .defaultConfiguration)
        manager = ResourceManager(cache: cache, downloadQueue: downloadQueue)
    }
    
    func setupWithPriorityQueue() async {
        let downloadQueue = DownloadQueue()
        await downloadQueue.add(processor: WebDownloadProcessor(configuration: .ephemeral))
        
        let priorityQueue = DownloadQueue()
        await priorityQueue.add(processor: WebDownloadProcessor.priorityProcessor())
        
        // Uses weighted mirror policy by default
        cache = RealmCacheManager<LocalFile>(configuration: .defaultConfiguration)
        manager = ResourceManager(cache: cache, downloadQueue: downloadQueue, priorityQueue: priorityQueue)
    }

    override func tearDownWithError() throws {
        // Note: skipping async cleanup in tearDown to avoid Task closure issues
        // This is acceptable for tests using in-memory database
        cache = nil
        manager = nil
    }
    
    func testRequestingEmptyArray() async throws {
        let requests = await manager.request(resources: [])
        XCTAssertEqual(requests.count, 0)
        let isActive = await manager.isActive
        XCTAssertEqual(isActive, true)
        let currentDownloadCount = await manager.currentDownloadCount
        XCTAssertEqual(currentDownloadCount, 0, "Manager should be empty.")
        let queuedDownloadCount = await manager.queuedDownloadCount
        XCTAssertEqual(queuedDownloadCount, 0, "Manager should be empty.")
        let downloads = await manager.downloads
        XCTAssertEqual(downloads.count, 0, "Manager should be empty.")
        let currentDownloads = await manager.currentDownloads
        XCTAssertEqual(currentDownloads.count, 0, "Manager should be empty.")
        let queuedDownloads = await manager.queuedDownloads
        XCTAssertEqual(queuedDownloads.count, 0, "Manager should be empty.")
        let hasDownloadable = await manager.hasDownloadable(with: "random-id")
        XCTAssertEqual(hasDownloadable, false, "Manager should be empty.")
        let downloadable = await manager.downloadable(for: "random-id")
        XCTAssertNil(downloadable, "Manager should be empty.")
        let isDownloading = await manager.isDownloading(for: "random-id")
        XCTAssertEqual(isDownloading, false, "Manager should be empty.")
    }
    
    func testRequestingDownloads() async throws {
        let requests = await manager.request(resources: resources)
        XCTAssertEqual(requests.count, 1)
        if let firstRequest = requests.first {
            let identifier = await firstRequest.downloadableIdentifier()
            XCTAssertEqual(identifier, "asset-id", "First downloadable should be the mirror with highest weight")
        }
    }
    
    func testRequestingDownloadsWithPriorityQueue() async throws {
        await setupWithPriorityQueue()
        
        let requests = await manager.request(resources: resources)
        XCTAssertEqual(requests.count, 1)
        if let firstRequest = requests.first {
            let identifier = await firstRequest.downloadableIdentifier()
            XCTAssertEqual(identifier, "asset-id", "First downloadable should be the mirror with highest weight")
        }
    }
    
    func testAssetCompletionIsCalled() async throws {
        let expectation = XCTestExpectation(description: "Requesting downloads should call completion.")
        
        await manager.request(resources: resources)
        await manager.addAssetCompletion(for: "asset-id") { (success, assetID) in
            XCTAssertTrue(success)
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 5)
    }
    
    func testThatMultipleAssetCompletionAreCalled() async throws {
        let expectation = self.expectation(description: "Requesting downloads should call completion.")
        expectation.expectedFulfillmentCount = 2
        
        let callCount = 0
        await manager.request(resources: resources)
        await manager.addAssetCompletion(for: "asset-id") { (success, assetID) in
            expectation.fulfill()
        }
        
        await manager.addAssetCompletion(for: "asset-id") { (success, assetID) in
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 5)
        XCTAssertEqual(callCount, 2, "Asset completion should be called two times")
    }
    
    func testThatAddingAssetCompletionBeforeRequestingDownloadsFails() async throws {
        let expectation = self.expectation(description: "Asset completion should be called immediately.")

        await manager.addAssetCompletion(for: "asset-id") { (success, assetID) in
            XCTAssertFalse(success)
            expectation.fulfill()
        }
        
        await manager.request(resources: resources)

        await fulfillment(of: [expectation], timeout: 2)
    }
    
    func testThatErrorHandlerIsCalled() async {
        let expectation = self.expectation(description: "Requesting downloads should call completion.")
        
        let asset = Asset(id: "invalid-asset", main: FileMirror(id: "invalid-asset",
                                                                location: "http://invalid.url/jpg",
                                                                info: [:]),
                          alternatives: [],
                          fileURL: nil)
        await manager.request(resources: [asset])
        await manager.addAssetCompletion(for: "invalid-asset") { (success, assetID) in
            XCTAssertFalse(success)
            XCTAssertEqual("invalid-asset", assetID)
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 5)
    }
    
    func testCancelingAllDownloads() async {
        let expectation = self.expectation(description: "Canceling all downloads should call completion.")
        
        await manager.request(resources: resources)
        await manager.addAssetCompletion(for: "asset-id") { (success, assetID) in
            XCTAssertFalse(success)
            XCTAssertEqual("asset-id", assetID)
            expectation.fulfill()
        }
        await manager.cancelAll()
        
        await fulfillment(of: [expectation], timeout: 1)
    }
    
    func testMakingManagerInactive() async {
        let expectation = self.expectation(description: "Completion should not be called.")
        expectation.isInverted = true // we don't want the expectation to be fulfilled
        
        await manager.cancelAll()
        let requests = await manager.request(resources: resources)
        await manager.addAssetCompletion(for: "asset-id") { (success, assetID) in
            expectation.fulfill()
        }
        
        // one request will be returned, but will never start executing
        XCTAssertEqual(requests.count, 1)
        
        await fulfillment(of: [expectation], timeout: 3)
    }
    
    func testMakingManagerActiveResumesDownloads() async {
        let expectation = self.expectation(description: "Completion should not be called.")
        
        await manager.cancelAll()
        let requests = await manager.request(resources: resources)
        await manager.addAssetCompletion(for: "asset-id") { (success, assetID) in
            XCTAssertTrue(success)
            expectation.fulfill()
        }
        
        await manager.request(resources: resources)
        
        // one request will be returned, but will never start executing
        XCTAssertEqual(requests.count, 1)
        
        await fulfillment(of: [expectation], timeout: 3)
    }

}
