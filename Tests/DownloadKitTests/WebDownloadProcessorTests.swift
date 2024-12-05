import XCTest
@testable import DownloadKit

struct MockItem: Downloadable {
    var transferredBytes: Int64 = .zero
    
    var priority: Int = 0
    
    var identifier: String = "identifier"
    
    var startDate: Date?
    
    var finishedDate: Date?
    
    var progress: Progress?
    
    func start(with parameters: DownloadParameters) {}
    
    func cancel() {}
    
    func pause() {}
    
    var description: String { return "MockItem: \(identifier)" }
}

class WebDownloadProcessorTests: XCTestCase {
    
    var processor: WebDownloadProcessor!
    var delegate: DownloadProcessorDelegateMock!
    
    override func setUpWithError() throws {
        delegate = DownloadProcessorDelegateMock()
        
        processor = WebDownloadProcessor(configuration: .ephemeral)
        processor.delegate = delegate
    }

    override func tearDownWithError() throws {
        processor.delegate = nil
        processor = nil
        delegate = nil
    }
    
    func testCanProcessWebDownloadItem() {
        let item = WebDownloadItem(identifier: "google-item", url: URL(string: "http://google.com")!)

        XCTAssertTrue(processor.canProcess(item: item))
    }

    func testCannotProcessWebDownloadItemIfInactive() {
        let item = WebDownloadItem(identifier: "google-item", url: URL(string: "http://google.com")!)

        processor.pause()
        XCTAssertFalse(processor.canProcess(item: item))
    }
    
    func testCanProcessItemAfterResumingProcessor() {
        let item = WebDownloadItem(identifier: "google-item", url: URL(string: "http://google.com")!)
        
        processor.pause()
        XCTAssertFalse(processor.canProcess(item: item))
        
        processor.resume()
        XCTAssertTrue(processor.canProcess(item: item))
    }

    func testCannotProcessMockItem() {
        XCTAssertFalse(processor.canProcess(item: MockItem()))
    }
    
    func testDownloadFinishesSuccessfully() throws {
        let item = WebDownloadItem.createSample()
        
        let expectation = XCTestExpectation(description: "Download should complete in few seconds.")
        
        delegate.finishTransferCallback = { url in
            XCTAssertFalse(url.absoluteString.isEmpty, "Download URL should not be empty")
            XCTAssertNotNil(try! Data(contentsOf: url), "We should be able to create Data object from contents of url")
            expectation.fulfill()
        }
        
        processor.process(item)
        
        wait(for: [expectation], timeout: 3)
    }
    
    func testDownloadFailsForInvalidURL() throws {
        let item = WebDownloadItem.invalidItem
        
        let expectation = XCTestExpectation(description: "Download should fail with error.")
        
        delegate.errorCallback = { error in
            XCTAssertNotNil(error)
            expectation.fulfill()
        }
        
        processor.process(item)
        
        wait(for: [expectation], timeout: 3)
    }
    
    func testEnqueuePendingWithPendingItems() {
        processor = WebDownloadProcessor(identifier: UUID().uuidString)
        processor.delegate = delegate
        
        processor.process(WebDownloadItem.createSample())
        processor.process(WebDownloadItem.createSample())
        processor.process(WebDownloadItem.createSample())
        processor.pause()
        
        let expectation = XCTestExpectation(description: "Enqueue function should execute delegate's beginCallback.")
        
        var executed = 0
        delegate.beginCallback = {
            // test is successful if we're getting called
            executed += 1
        }
        
        processor.enqueuePending {
            XCTAssertEqual(executed, 3, "Begin callback should be called on processor because we had pending items.")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5)
    }
}

extension WebDownloadItem {
    static func createSample() -> WebDownloadItem {
        return WebDownloadItem(identifier: UUID().uuidString,
                               url: URL(string: "https://picsum.photos/100")!)
    }
    
    static let invalidItem = WebDownloadItem(identifier: "invalid-item-identifier",
                                             url: URL(string: "https://ljkasdlkas.com/asdasdas/image.jpg")!)
}
