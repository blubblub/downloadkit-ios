//
//  WaitTillCompleteTests.swift
//  DownloadKitTests
//
//  Created by Assistant on 2025-07-02.
//

import XCTest
@testable import DownloadKit
@testable import DownloadKitRealm

class WaitTillCompleteTests: XCTestCase {
    
    func testWaitTillCompleteWithSingleDownload() async throws {
        // Create a simple resource manager
        let cache = RealmCacheManager<CachedLocalFile>(configuration: .defaultConfiguration)
        let downloadQueue = DownloadQueue()
        await downloadQueue.add(processor: WebDownloadProcessor(configuration: .ephemeral))
        
        let manager = ResourceManager(cache: cache, downloadQueue: downloadQueue)
        
        // Create a test resource
        let resource = Resource(
            id: "wait-test-resource",
            main: FileMirror(
                id: "wait-test-mirror",
                location: "https://picsum.photos/100/100.jpg",
                info: [:]
            ),
            alternatives: [],
            fileURL: nil
        )
        
        // Request download
        let requests = await manager.request(resources: [resource])
        guard let request = requests.first else {
            XCTFail("Should have created a download request")
            return
        }
        
        // Process the request
        await manager.process(requests: requests)
        
        // Record start time
        let startTime = Date()
        
        // Wait for completion
        do {
            try await request.waitTillComplete()
            
            let duration = Date().timeIntervalSince(startTime)
            print("✅ Download completed successfully in \(String(format: "%.2f", duration)) seconds")
            
            // Verify the downloadable has a finished date set
            let finishedDate = await request.mirror.downloadable.finishedDate
            XCTAssertNotNil(finishedDate, "Download should have a finished date after completion")
            
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            print("❌ Download failed after \(String(format: "%.2f", duration)) seconds with error: \(error)")
            
            // Even in failure case, finishedDate should be set
            let finishedDate = await request.mirror.downloadable.finishedDate
            XCTAssertNotNil(finishedDate, "Download should have a finished date even after failure")
            
            // Re-throw the error if it's not expected
            throw error
        }
    }
    
    func testWaitTillCompleteWithAlreadyCompletedDownload() async throws {
        // Create a CloudKit download that we can manually finish
        let cloudKitDownload = CloudKitDownload(
            identifier: "already-completed-test",
            url: URL(string: "cloudkit://container/record_type/record_id")!
        )
        
        // Manually finish the download
        await cloudKitDownload.finish()
        
        // Create a mock request
        let mirror = ResourceMirrorSelection(
            id: "test-id",
            mirror: FileMirror(id: "test-mirror", location: "cloudkit://test", info: [:]),
            downloadable: cloudKitDownload
        )
        
        let resource = Resource(
            id: "test-resource",
            main: FileMirror(id: "test-mirror", location: "cloudkit://test", info: [:]),
            alternatives: [],
            fileURL: nil
        )
        
        let request = DownloadRequest(
            resource: resource,
            options: RequestOptions(),
            mirror: mirror
        )
        
        // Record start time
        let startTime = Date()
        
        // Wait for completion - should return immediately since download is already finished
        try await request.waitTillComplete()
        
        let duration = Date().timeIntervalSince(startTime)
        print("✅ Already completed download returned in \(String(format: "%.4f", duration)) seconds")
        
        // Should return very quickly since download was already finished
        XCTAssertLessThan(duration, 0.1, "waitTillComplete should return immediately for already completed downloads")
        
        // Verify the downloadable has a finished date
        let finishedDate = await request.mirror.downloadable.finishedDate
        XCTAssertNotNil(finishedDate, "Download should have a finished date")
    }
    
    func testWaitTillCompleteWithCancellation() async throws {
        // Create a test download
        let webDownload = WebDownload(
            identifier: "cancellation-test",
            url: URL(string: "https://httpbin.org/delay/10")! // Slow endpoint for testing cancellation
        )
        
        let mirror = ResourceMirrorSelection(
            id: "cancellation-test-id",
            mirror: FileMirror(id: "cancellation-test-mirror", location: "https://httpbin.org/delay/10", info: [:]),
            downloadable: webDownload
        )
        
        let resource = Resource(
            id: "cancellation-test-resource",
            main: FileMirror(id: "cancellation-test-mirror", location: "https://httpbin.org/delay/10", info: [:]),
            alternatives: [],
            fileURL: nil
        )
        
        let request = DownloadRequest(
            resource: resource,
            options: RequestOptions(),
            mirror: mirror
        )
        
        // Start a task that will wait for completion
        let waitTask = Task {
            try await request.waitTillComplete()
        }
        
        // Cancel the task after a short delay
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        waitTask.cancel()
        
        // Verify that the wait was cancelled
        do {
            try await waitTask.value
            XCTFail("waitTillComplete should have been cancelled")
        } catch is CancellationError {
            // Expected - cancellation was handled correctly
            print("✅ Cancellation handled correctly")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
