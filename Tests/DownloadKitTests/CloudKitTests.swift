import XCTest
import CloudKit
@testable import DownloadKit

class CloudKitTests: XCTestCase, @unchecked Sendable {
    
    var cloudKitDownload: CloudKitDownload!
    var processor: CloudKitDownloadProcessor!
    var delegate: DownloadProcessorDelegateMock!
    
    override func setUpWithError() throws {
        delegate = DownloadProcessorDelegateMock()
        
        // Create CloudKit downloads with test URLs (skip processor creation to avoid CloudKit setup)
        cloudKitDownload = CloudKitDownload(identifier: "test-cloudkit-item", 
                                          url: URL(string: "cloudkit://container/record_type/record_id")!)
    }
    
    override func tearDownWithError() throws {
        cloudKitDownload = nil
        processor = nil
        delegate = nil
    }
    
    // MARK: - CloudKitDownload Tests
    
    func testCloudKitDownloadInitialization() async {
        let identifier = await cloudKitDownload.identifier
        let priority = await cloudKitDownload.priority
        let totalBytes = await cloudKitDownload.totalBytes
        let totalSize = await cloudKitDownload.totalSize
        let transferredBytes = await cloudKitDownload.transferredBytes
        let startDate = await cloudKitDownload.startDate
        let finishedDate = await cloudKitDownload.finishedDate
        
        XCTAssertEqual(identifier, "test-cloudkit-item")
        XCTAssertEqual(priority, 0)
        XCTAssertEqual(totalBytes, 0)
        XCTAssertEqual(totalSize, 0)
        XCTAssertEqual(transferredBytes, 0)
        XCTAssertNil(startDate)
        XCTAssertNil(finishedDate)
    }
    
    func testCloudKitDownloadWithPriority() async {
        let priorityDownload = CloudKitDownload(identifier: "priority-item", 
                                              url: URL(string: "cloudkit://container/record_type/record_id")!, 
                                              priority: 100)
        let initialPriority = await priorityDownload.priority
        XCTAssertEqual(initialPriority, 100)
        
        await priorityDownload.set(priority: 200)
        let updatedPriority = await priorityDownload.priority
        XCTAssertEqual(updatedPriority, 200)
    }
    
    func testCloudKitDownloadProgress() async {
        // Test initial progress is nil
        let initialProgress = await cloudKitDownload.progress
        XCTAssertNil(initialProgress)
        
        // Set total size to trigger progress creation
        await cloudKitDownload.update(totalBytes: 1000)
        
        // Update progress
        await cloudKitDownload.update(progress: 0.5)
        let transferredBytes = await cloudKitDownload.transferredBytes
        XCTAssertEqual(transferredBytes, 0) // totalSize is 0, so no transfer
        
        // Test progress with totalSize
        let downloadWithSize = CloudKitDownload(identifier: "size-test", 
                                               url: URL(string: "cloudkit://container/record_type/record_id")!)
        await downloadWithSize.update(totalBytes: 2000)
        await downloadWithSize.update(progress: 0.5)
        // Progress should be calculated based on totalSize if available
    }
    
    func testCloudKitDownloadLifecycle() async {
        // Test start
        await cloudKitDownload.start(with: [:])
        let startDate = await cloudKitDownload.startDate
        XCTAssertNotNil(startDate)
        
        // Test finish
        await cloudKitDownload.finish()
        let finishedDate = await cloudKitDownload.finishedDate
        XCTAssertNotNil(finishedDate)
        
        // Test pause and cancel don't crash
        await cloudKitDownload.pause()
        await cloudKitDownload.cancel()
    }
    
    func testCloudKitDownloadDescription() async {
        let description = await cloudKitDownload.description
        XCTAssertTrue(description.contains("CloudKitItem"))
        XCTAssertTrue(description.contains("test-cloudkit-item"))
    }
    
    // MARK: - CloudKit Record ID Parsing Tests
    
    func testRecordIDParsingSimpleFormat() async {
        let simpleDownload = CloudKitDownload(identifier: "simple-test", 
                                            url: URL(string: "cloudkit://container/record_type/record_id")!)
        let recordID = await simpleDownload.recordID
        XCTAssertNotNil(recordID)
        XCTAssertEqual(recordID?.recordName, "record_id")
    }
    
    func testRecordIDParsingComplexFormat() async {
        let complexDownload = CloudKitDownload(identifier: "complex-test", 
                                             url: URL(string: "cloudkit://container/zone_id/zone_owner/record_type/record_id")!)
        let recordID = await complexDownload.recordID
        XCTAssertNotNil(recordID)
        XCTAssertEqual(recordID?.recordName, "record_id")
        XCTAssertEqual(recordID?.zoneID.zoneName, "zone_id")
        XCTAssertEqual(recordID?.zoneID.ownerName, "zone_owner")
    }
    
    func testRecordIDParsingInvalidFormat() async {
        let invalidDownload = CloudKitDownload(identifier: "invalid-test", 
                                             url: URL(string: "cloudkit://invalid")!)
        let recordID = await invalidDownload.recordID
        XCTAssertNil(recordID)
    }
    
    // MARK: - CloudKitDownloadProcessor Tests
    // Note: These tests are commented out as they require CloudKit infrastructure setup
    
    /*
    func testProcessorInitialization() async {
        await processor.set(delegate: delegate)
        let isActive = await processor.isActive
        let throttlingEnabled = await processor.throttlingProtectionEnabled
        XCTAssertTrue(isActive)
        XCTAssertTrue(throttlingEnabled)
    }
    
    func testProcessorCanProcessCloudKitDownload() async {
        let canProcess = await processor.canProcess(downloadable: cloudKitDownload)
        XCTAssertTrue(canProcess)
    }
    
    func testProcessorCannotProcessWhenInactive() async {
        await processor.pause()
        let canProcess = await processor.canProcess(downloadable: cloudKitDownload)
        XCTAssertFalse(canProcess)
    }
    
    func testProcessorCannotProcessNonCloudKitDownload() async {
        let webDownload = WebDownload(identifier: "web-test", url: URL(string: "https://example.com")!)
        let canProcess = await processor.canProcess(downloadable: webDownload)
        XCTAssertFalse(canProcess)
    }
    
    func testProcessorHandlesDownloadWithNoRecordID() async {
        await processor.set(delegate: delegate)
        
        let expectation = XCTestExpectation(description: "Error callback should be called for no record ID")
        
        Task { [delegate = delegate!] in
            await delegate.setErrorCallback { (error: Error) in
                if case CloudKitError.noRecord = error {
                    expectation.fulfill()
                }
            }
        }
        
        let invalidDownload = CloudKitDownload(identifier: "no-record-test", 
                                             url: URL(string: "cloudkit://invalid")!)
        
        await processor.process(invalidDownload)
        
        await fulfillment(of: [expectation], timeout: 1)
    }
    
    func testProcessorThrottlingBehavior() async {
        await processor.set(delegate: delegate)
        
        // Test with throttling enabled
        let throttlingEnabled = await processor.throttlingProtectionEnabled
        XCTAssertTrue(throttlingEnabled)
        
        // Multiple rapid calls should be throttled
        let download1 = CloudKitDownload(identifier: "throttle-test-1", 
                                       url: URL(string: "cloudkit://container/type/id1")!)
        let download2 = CloudKitDownload(identifier: "throttle-test-2", 
                                       url: URL(string: "cloudkit://container/type/id2")!)
        
        await processor.process(download1)
        await processor.process(download2)
        
        // Both should be queued for processing
    }
    
    func testProcessorWithoutThrottling() async {
        await processor.set(delegate: delegate)
        
        // Disable throttling
        await processor.set(throttlingProtectionEnabled: false)
        let throttlingAfterDisable = await processor.throttlingProtectionEnabled
        XCTAssertFalse(throttlingAfterDisable)
        
        let download = CloudKitDownload(identifier: "no-throttle-test", 
                                      url: URL(string: "cloudkit://container/type/id")!)
        
        await processor.process(download)
        // Should process immediately without throttling
    }
    
    func testProcessorEnqueuePending() async {
        // Test enqueuePending method
        await processor.enqueuePending()
        // This is a no-op for CloudKit, but should not crash
    }
    
    func testProcessorPauseAndResume() async {
        await processor.pause()
        await processor.resume()
        // These are no-ops for CloudKit, but should not crash
    }
    */
    
    // MARK: - Error Handling Tests
    
    func testCloudKitErrorTypes() {
        let noAssetError = CloudKitError.noAssetData
        let noRecordError = CloudKitError.noRecord
        
        XCTAssertNotNil(noAssetError)
        XCTAssertNotNil(noRecordError)
        
        // Test that errors are different types
        if case .noAssetData = noAssetError {
            // Expected
        } else {
            XCTFail("Should be noAssetData")
        }
        
        if case .noRecord = noRecordError {
            // Expected
        } else {
            XCTFail("Should be noRecord")
        }
    }
}


// MARK: - CloudKitDownloadProcessor Extensions for Testing

extension CloudKitDownloadProcessor {
    func set(throttlingProtectionEnabled: Bool) async {
        self.throttlingProtectionEnabled = throttlingProtectionEnabled
    }
}
