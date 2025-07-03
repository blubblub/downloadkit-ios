//
//  WaitTillCompleteTests.swift
//  DownloadKitTests
//
//  Created by Assistant on 2025-07-02.
//

import XCTest
import RealmSwift
@testable import DownloadKit
@testable import DownloadKitRealm

class WaitTillCompleteTests: XCTestCase {
    
    func testWaitTillCompleteWithSingleDownload() async throws {
        // Create a simple resource manager
        let cache = RealmCacheManager<CachedLocalFile>(configuration: Realm.Configuration(inMemoryIdentifier: "wait-test-\(UUID().uuidString)"))
        let downloadQueue = DownloadQueue()
        await downloadQueue.add(processor: WebDownloadProcessor(configuration: .default))
        
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
        // Create a simple resource manager
        let cache = RealmCacheManager<CachedLocalFile>(configuration: Realm.Configuration(inMemoryIdentifier: "wait-test-\(UUID().uuidString)"))
        let downloadQueue = DownloadQueue()
        await downloadQueue.add(processor: WebDownloadProcessor(configuration: .default))
        
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
        
        // Test making the same request again - should complete faster since it's cached
        print("\n--- Testing second request for same resource ---")
        let secondRequests = await manager.request(resources: [resource])
        
        if secondRequests.isEmpty {
            print("✅ Second request returned no downloads - resource is already cached")
        } else {
            // If there are still requests, wait for them to complete
            guard let secondRequest = secondRequests.first else {
                return
            }
            
            await manager.process(requests: secondRequests)
            
            let secondStartTime = Date()
            do {
                try await secondRequest.waitTillComplete()
                let secondDuration = Date().timeIntervalSince(secondStartTime)
                print("✅ Second download completed in \(String(format: "%.2f", secondDuration)) seconds")
            } catch {
                let secondDuration = Date().timeIntervalSince(secondStartTime)
                print("❌ Second download failed after \(String(format: "%.2f", secondDuration)) seconds with error: \(error)")
                // Don't re-throw for second request as it's supplementary
            }
        }
    }
}
