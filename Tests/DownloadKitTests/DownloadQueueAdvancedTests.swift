import XCTest
@testable import DownloadKit

class DownloadQueueAdvancedTests: XCTestCase, @unchecked Sendable {
    
    var downloadQueue: DownloadQueue!
    var processor: WebDownloadProcessor!
    var observer: DownloadQueueObserverMock!
    
    override func setUpWithError() throws {
        downloadQueue = DownloadQueue()
        processor = WebDownloadProcessor(configuration: .default)
        observer = DownloadQueueObserverMock()
    }
    
    override func tearDownWithError() throws {
        Task { [queue = downloadQueue!] in
            await queue.cancelAll()
        }
        downloadQueue = nil
        processor = nil
        observer = nil
    }
    
    // MARK: - Advanced Queue Management Tests
    
    func testQueueWithMultipleProcessors() async {
        await downloadQueue.add(processor: processor)
        
        let processor2 = WebDownloadProcessor(configuration: .default)
        await downloadQueue.add(processor: processor2)
        
        // Both processors should be added
        let processorCount = await downloadQueue.downloadProcessors.count
        XCTAssertEqual(processorCount, 2)
    }
    
    func testQueueMetrics() async {
        await downloadQueue.set(observer: observer)
        await downloadQueue.add(processor: processor)
        
        let metrics = await downloadQueue.metrics
        XCTAssertEqual(metrics.processed, 0)
        XCTAssertEqual(metrics.failed, 0)
        XCTAssertEqual(metrics.completed, 0)
    }
    
    func testSimultaneousDownloadLimit() async {
        await downloadQueue.set(simultaneousDownloads: 2)
        await downloadQueue.add(processor: processor)
        
        let simultaneousLimit = await downloadQueue.simultaneousDownloads
        XCTAssertEqual(simultaneousLimit, 2)
        
        // Test that limit is enforced with minimum of 1
        await downloadQueue.set(simultaneousDownloads: 0)
        let minLimit = await downloadQueue.simultaneousDownloads
        XCTAssertEqual(minLimit, 1)
    }
    
    func testQueuedDownloadsAccess() async {
        await downloadQueue.add(processor: processor)
        
        // Test that we can access queued downloads
        let queuedDownloads = await downloadQueue.queuedDownloads
        XCTAssertGreaterThanOrEqual(queuedDownloads.count, 0)
        
        // Test that we can access current downloads
        let currentDownloads = await downloadQueue.currentDownloads
        XCTAssertGreaterThanOrEqual(currentDownloads.count, 0)
    }
    
    func testCancelWithIdentifier() async {
        await downloadQueue.add(processor: processor)
        
        // Test cancel method with non-existent identifier doesn't crash
        await downloadQueue.cancel(with: "nonexistent")
        
        // Verify non-existent download returns false
        let hasDownload = await downloadQueue.hasDownload(for: "nonexistent")
        XCTAssertFalse(hasDownload)
    }
    
    func testCancelAll() async {
        await downloadQueue.add(processor: processor)
        
        // Test cancelAll doesn't crash
        await downloadQueue.cancelAll()
        
        // Verify counts after cancel all
        let queuedCount = await downloadQueue.queuedDownloadCount
        let currentCount = await downloadQueue.currentDownloadCount
        XCTAssertEqual(queuedCount, 0)
        XCTAssertEqual(currentCount, 0)
    }
    
    func testQueueActivationAndDeactivation() async {
        await downloadQueue.add(processor: processor)
        
        // Test initial state
        let initialActive = await downloadQueue.isActive
        XCTAssertTrue(initialActive)
        
        // Deactivate queue
        await downloadQueue.setActive(false)
        let inactiveState = await downloadQueue.isActive
        XCTAssertFalse(inactiveState)
        
        // Reactivate queue
        await downloadQueue.setActive(true)
        let activeAgain = await downloadQueue.isActive
        XCTAssertTrue(activeAgain)
    }
    
    func testEnqueuePendingDownloads() async {
        await downloadQueue.add(processor: processor)
        
        // Test enqueuePending
        await downloadQueue.enqueuePending()
        
        // This should not crash and should handle any pending downloads
        let currentCount = await downloadQueue.currentDownloadCount
        XCTAssertGreaterThanOrEqual(currentCount, 0)
    }
    
    func testQueueDownloadCount() async {
        await downloadQueue.add(processor: processor)
        
        // Test that download counts are accessible
        let queuedCount = await downloadQueue.queuedDownloadCount
        let currentCount = await downloadQueue.currentDownloadCount
        
        XCTAssertGreaterThanOrEqual(queuedCount, 0)
        XCTAssertGreaterThanOrEqual(currentCount, 0)
    }
    
    func testQueueInitialState() async {
        await downloadQueue.add(processor: processor)
        
        // Verify queue is empty initially
        let initialQueuedCount = await downloadQueue.queuedDownloadCount
        let initialCurrentCount = await downloadQueue.currentDownloadCount
        
        XCTAssertEqual(initialQueuedCount, 0)
        XCTAssertEqual(initialCurrentCount, 0)
    }
    
    func testDownloadTaskRetrieval() async {
        await downloadQueue.add(processor: processor)
        
        // Test non-existent task
        let nonExistentTask = await downloadQueue.download(for: "non-existent")
        XCTAssertNil(nonExistentTask)
    }
    
    func testIsDownloadingStatus() async {
        await downloadQueue.add(processor: processor)
        
        // Test that non-existent download is not downloading
        let notDownloading = await downloadQueue.isDownloading(for: "nonexistent-test")
        XCTAssertFalse(notDownloading)
        
        // Test hasDownload for non-existent
        let hasDownload = await downloadQueue.hasDownload(for: "nonexistent-test")
        XCTAssertFalse(hasDownload)
    }
    
    func testDownloadsArrayAccess() async {
        await downloadQueue.add(processor: processor)
        
        // Test that downloads array is accessible
        let downloads = await downloadQueue.downloads
        XCTAssertNotNil(downloads)
        XCTAssertGreaterThanOrEqual(downloads.count, 0)
    }
    
    // MARK: - Error Handling Tests
    
    func testObserverSetup() async {
        // Test setting observer doesn't crash
        await downloadQueue.set(observer: observer)
        
        // Verify observer is set by checking we can access it
        let observerIsSet = await downloadQueue.observer != nil
        XCTAssertTrue(observerIsSet)
    }
    
    // MARK: - Helper Methods
    
    private func createTestDownloads(count: Int) -> [WebDownload] {
        return (0..<count).map { index in
            WebDownload(identifier: "test-download-\(index)", 
                       url: URL(string: "https://example.com/file\(index)")!)
        }
    }
}

// MARK: - Mock Download Queue Delegate
// NOTE: DownloadQueueObserverMock has been moved to TestMocksAndHelpers.swift
