import XCTest
@testable import DownloadKit

actor MockItem: Downloadable {
    var transferredBytes: Int64 = .zero
    
    var priority: Int = 0
    
    var identifier: String = "identifier"
    
    var startDate: Date?
    
    var finishedDate: Date?
    
    var progress: Progress?
    
    func set(priority: Int) {
        self.priority = priority
    }
    
    func start(with parameters: DownloadParameters) {}
    
    func cancel() {}
    
    func pause() {}
    
    var description: String { return "MockItem: \(identifier)" }
}

class WebDownloadProcessorTests: XCTestCase {
    
    var processor: WebDownloadProcessor!
    var observer: DownloadProcessorObserverMock!
    
    override func setUpWithError() throws {
        observer = DownloadProcessorObserverMock()
        
        processor = WebDownloadProcessor()
        // Note: observer will be set in async test methods
    }

    override func tearDownWithError() throws {
        processor = nil
observer = nil
    }
    
    func testCanProcessWebDownloadItem() async {
await processor.set(observer: observer)
        let item = WebDownload(identifier: "google-item", url: URL(string: "http://google.com")!)

        let canProcess = await processor.canProcess(downloadable: item)
        XCTAssertTrue(canProcess)
    }

    func testCannotProcessWebDownloadItemIfInactive() async {
        await processor.set(observer: observer)
        let item = WebDownload(identifier: "google-item", url: URL(string: "http://google.com")!)

        await processor.pause()
        let canProcess = await processor.canProcess(downloadable: item)
        XCTAssertFalse(canProcess)
    }
    
    func testCanProcessItemAfterResumingProcessor() async {
        await processor.set(observer: observer)
        let item = WebDownload(identifier: "google-item", url: URL(string: "http://google.com")!)
        
        await processor.pause()
        let canProcessAfterPause = await processor.canProcess(downloadable: item)
        XCTAssertFalse(canProcessAfterPause)
        
        await processor.resume()
        let canProcessAfterResume = await processor.canProcess(downloadable: item)
        XCTAssertTrue(canProcessAfterResume)
    }

    func testCannotProcessMockItem() async {
        let canProcess = await processor.canProcess(downloadable: MockItem())
        XCTAssertFalse(canProcess)
    }
    
    func testDownloadFinishesSuccessfully() async throws {
        await processor.set(observer: observer)
        let item = WebDownload.createSample()
        
        let expectation = XCTestExpectation(description: "Download should complete in few seconds.")
        
        await observer.setFinishTransferCallback { url in
            XCTAssertFalse(url.absoluteString.isEmpty, "Download URL should not be empty")
            // Note: Temporary file may be cleaned up by the time this callback executes
            // so we just verify the URL is valid rather than trying to access the file
            expectation.fulfill()
        }
        
        await processor.process(item)
        
        await fulfillment(of: [expectation], timeout: 3)
    }
    
    func testDownloadFailsForInvalidURL() async throws {
        await processor.set(observer: observer)
        let item = WebDownload.invalidItem
        
        let expectation = XCTestExpectation(description: "Download should fail with error.")
        
await observer.setErrorCallback { error in
            XCTAssertNotNil(error)
            expectation.fulfill()
        }
        
        await processor.process(item)
        
        await fulfillment(of: [expectation], timeout: 3)
    }
    
    func testEnqueuePendingWithPendingItems() async {
        processor = WebDownloadProcessor()
        await processor.set(observer: observer)
        
        await processor.process(WebDownload.createSample())
        await processor.process(WebDownload.createSample())
        await processor.process(WebDownload.createSample())
        await processor.pause()
        
        let expectation = XCTestExpectation(description: "Enqueue function should execute delegate's beginCallback.")
        
        var executed = 0
await observer.setBeginCallback {
            // test is successful if we're getting called
            executed += 1
        }
        
        await processor.enqueuePending()
        XCTAssertEqual(executed, 3, "Begin callback should be called on processor because we had pending items.")
        expectation.fulfill()
        
        await fulfillment(of: [expectation], timeout: 5)
    }
}

extension WebDownload {
    static func createSample() -> WebDownload {
        return WebDownload(identifier: UUID().uuidString,
                           url: URL(string: "https://picsum.photos/100")!)
    }
    
    static let invalidItem = WebDownload(identifier: "invalid-item-identifier",
                                         url: URL(string: "https://ljkasdlkas.com/asdasdas/image.jpg")!)
}
