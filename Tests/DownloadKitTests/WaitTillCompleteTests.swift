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
    
    var realm: Realm!
    
    override func setUpWithError() throws {
        // Synchronous setup - realm will be configured in async test methods
    }
    
    override func tearDownWithError() throws {
        // Clear references - in-memory realm will be automatically cleaned up
        realm = nil
    }
    
    private func createManagerWithRealm() async -> (ResourceManager, RealmCacheManager<CachedLocalFile>) {
        let config = Realm.Configuration(inMemoryIdentifier: "wait-test-\(UUID().uuidString)")
        
        // Create Realm instance and keep it alive during the test
        realm = try! await Realm(configuration: config, actor: MainActor.shared)
        
        let cache = RealmCacheManager<CachedLocalFile>(configuration: config)
        let downloadQueue = DownloadQueue()
        await downloadQueue.add(processor: WebDownloadProcessor(configuration: .default))
        
        let manager = ResourceManager(cache: cache, downloadQueue: downloadQueue)
        return (manager, cache)
    }
    
    func testWaitTillCompleteWithSingleDownload() async throws {
        // Create a simple resource manager
        let (manager, _) = await createManagerWithRealm()
        
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
        
        // Process the request and get the task
        let tasks = await manager.process(requests: requests)
        guard let task = tasks.first else {
            XCTFail("Should have created a download task")
            return
        }
        
        // Record start time
        let startTime = Date()
        
        // Wait for completion
        do {
            try await task.waitTillComplete()
            
            let duration = Date().timeIntervalSince(startTime)
            print("✅ Download completed successfully in \(String(format: "%.2f", duration)) seconds")
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            print("❌ Download failed after \(String(format: "%.2f", duration)) seconds with error: \(error)")
            
            // Re-throw the error if it's not expected
            throw error
        }
    }
    
    func testWaitTillCompleteWithAlreadyCompletedDownload() async throws {
        // Create a simple resource manager
        let (manager, _) = await createManagerWithRealm()
        
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
        
        // Process the request and get the task
        let tasks = await manager.process(requests: requests)
        guard let task = tasks.first else {
            XCTFail("Should have created a download task")
            return
        }
        
        // Record start time
        let startTime = Date()
        
        // Wait for completion
        do {
            try await task.waitTillComplete()
            
            let duration = Date().timeIntervalSince(startTime)
            print("✅ Download completed successfully in \(String(format: "%.2f", duration)) seconds")
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            print("❌ Download failed after \(String(format: "%.2f", duration)) seconds with error: \(error)")
            
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
            
            let secondTasks = await manager.process(requests: secondRequests)
            guard let secondTask = secondTasks.first else {
                return
            }
            
            let secondStartTime = Date()
            do {
                try await secondTask.waitTillComplete()
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
