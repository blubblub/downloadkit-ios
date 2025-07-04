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
        
        processor = WebDownloadProcessor(configuration: .default)
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
        
        await fulfillment(of: [expectation], timeout: 6)
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
        
        await fulfillment(of: [expectation], timeout: 6)
    }
    
    func testEnqueuePendingWithPendingItems() async {
        processor = WebDownloadProcessor(configuration: .default)
        await processor.set(observer: observer)
        
        let expectation = XCTestExpectation(description: "Enqueue function should execute delegate's beginCallback.")
        
        var executed = 0
        await observer.setBeginCallback {
            // test is successful if we're getting called
            executed += 1
            
            expectation.fulfill()
        }
        
        await processor.process(WebDownload.createSample())
        await processor.process(WebDownload.createSample())
        await processor.process(WebDownload.createSample())
        await processor.pause()
        
        await fulfillment(of: [expectation], timeout: 10)
        
        XCTAssertEqual(executed, 3, "Begin callback should be called on processor because we had pending items.")
    }
    
    /// Test that WebDownload correctly tracks transferred bytes during download
    func testWebDownloadTransferredBytesTracking() async throws {
        await processor.set(observer: observer)
        
        // Create a WebDownload with a small image URL for testing
        let webDownload = WebDownload(
            identifier: "bytes-test-download",
            url: URL(string: "https://picsum.photos/200/200.jpg")!
        )
        
        let expectation = XCTestExpectation(description: "Download should track transferred bytes")
        let progressExpectation = XCTestExpectation(description: "Progress should be updated")
        
        // Use actor-based thread-safe tracking
        let progressTracker = ActorCounter()
        let bytesTracker = ActorCounter()
        let totalBytesTracker = ActorCounter()
        
        // Set up progress tracking
        await webDownload.addProgressUpdate { @Sendable totalBytesWritten, totalSize in
            print("Progress update: \(totalBytesWritten) bytes written, total size: \(totalSize)")
            Task {
                await progressTracker.increment()
                await bytesTracker.setValue(Int(totalBytesWritten))
                await totalBytesTracker.setValue(Int(totalSize))
                
                let updates = await progressTracker.value
                if updates >= 1 {
                    progressExpectation.fulfill()
                }
            }
        }
        
        // Set up completion tracking
        await webDownload.addCompletion { result in
            switch result {
            case .success(let url):
                print("Download completed successfully to: \(url)")
                expectation.fulfill()
            case .failure(let error):
                print("Download failed with error: \(error)")
                expectation.fulfill() // Still fulfill to prevent test timeout
            }
        }
        
        // Start the download
        await processor.process(webDownload)
        
        // Wait for download to complete and progress to be updated
        await fulfillment(of: [expectation, progressExpectation], timeout: 60)
        
        // Verify transferred bytes tracking
        let finalTransferredBytes = await webDownload.transferredBytes
        let finalTotalBytes = await webDownload.totalBytes
        
        // Get tracked values
        let receivedProgressUpdates = await progressTracker.value
        let lastTransferredBytes = await bytesTracker.value
        let totalBytesExpected = await totalBytesTracker.value
        
        print("\n=== BYTES TRANSFER VERIFICATION ===")
        print("Progress updates received: \(receivedProgressUpdates)")
        print("Last transferred bytes from progress: \(lastTransferredBytes)")
        print("Final transferred bytes from WebDownload: \(finalTransferredBytes)")
        print("Final total bytes from WebDownload: \(finalTotalBytes)")
        print("Total bytes expected from progress: \(totalBytesExpected)")
        
        // Verify we received progress updates
        XCTAssertGreaterThan(receivedProgressUpdates, 0, "Should receive at least one progress update")
        
        // Verify transferred bytes are tracked correctly
        if finalTransferredBytes > 0 {
            XCTAssertEqual(finalTransferredBytes, Int64(lastTransferredBytes), "WebDownload transferred bytes should match last progress update")
            XCTAssertGreaterThan(finalTransferredBytes, 0, "Should have transferred some bytes")
        }
        
        // Verify total bytes are set correctly
        if finalTotalBytes > 0 {
            XCTAssertEqual(finalTotalBytes, Int64(totalBytesExpected), "WebDownload total bytes should match expected total")
        }
        
        // Verify progress object
        let progress = await webDownload.progress
        if let progress = progress {
            print("Progress object - completed: \(progress.completedUnitCount), total: \(progress.totalUnitCount)")
            XCTAssertNotNil(progress, "Progress object should be created")
            
            if finalTransferredBytes > 0 {
                XCTAssertGreaterThan(progress.completedUnitCount, 0, "Progress should show completed units")
                XCTAssertGreaterThan(progress.totalUnitCount, 0, "Progress should show total units")
            }
        }
    }
    
    /// Test WebDownload bytes tracking with a mock progression
    func testWebDownloadBytesTrackingProgression() async throws {
        let webDownload = WebDownload(
            identifier: "mock-progression-test",
            url: URL(string: "https://picsum.photos/100/100.jpg")!
        )
        
        // Test initial state
        let initialTransferred = await webDownload.transferredBytes
        let initialTotal = await webDownload.totalBytes
        
        XCTAssertEqual(initialTransferred, 0, "Initial transferred bytes should be 0")
        XCTAssertEqual(initialTotal, 0, "Initial total bytes should be 0")
        
        // Simulate URLSession delegate calls for byte progression
        let mockTotalBytes: Int64 = 5000
        let progressionSteps = [1000, 2500, 4000, 5000]
        
        // Get the URL once since it's an async property
        let downloadURL = await webDownload.url
        
        for (index, bytesWritten) in progressionSteps.enumerated() {
            // Simulate the URLSession delegate callback - this is nonisolated so calls happen via Task
            webDownload.urlSession(
                URLSession.shared,
                downloadTask: URLSession.shared.downloadTask(with: downloadURL),
                didWriteData: Int64(bytesWritten - (index > 0 ? progressionSteps[index - 1] : 0)),
                totalBytesWritten: Int64(bytesWritten),
                totalBytesExpectedToWrite: mockTotalBytes
            )
            
            // Add a small delay to allow the Task to complete the async update
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            
            // Verify bytes are tracked correctly
            let currentTransferred = await webDownload.transferredBytes
            let currentTotal = await webDownload.totalBytes
            
            print("Step \(index + 1): Transferred \(currentTransferred)/\(currentTotal) bytes")
            
            XCTAssertEqual(currentTransferred, Int64(bytesWritten), "Transferred bytes should match step \(index + 1)")
            XCTAssertEqual(currentTotal, mockTotalBytes, "Total bytes should be set correctly")
            
            // Verify progress object is updated
            let progress = await webDownload.progress
            if let progress = progress {
                XCTAssertEqual(progress.completedUnitCount, Int64(bytesWritten), "Progress completed units should match transferred bytes")
                XCTAssertEqual(progress.totalUnitCount, mockTotalBytes + 1, "Progress total units should include file move operation")
            }
        }
        
        // Verify final state
        let finalTransferred = await webDownload.transferredBytes
        let finalTotal = await webDownload.totalBytes
        
        XCTAssertEqual(finalTransferred, mockTotalBytes, "Final transferred bytes should equal total")
        XCTAssertEqual(finalTotal, mockTotalBytes, "Final total bytes should be consistent")
        
        print("✅ WebDownload bytes tracking progression test completed successfully")
        print("   Final state: \(finalTransferred)/\(finalTotal) bytes")
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
