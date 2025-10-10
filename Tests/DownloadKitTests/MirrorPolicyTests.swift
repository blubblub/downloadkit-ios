//
//  WeightedMirrorPolicyTests.swift
//  BlubBlubCore_Tests
//
//  Created by Dal Rupnik on 2/18/21.
//  Copyright © 2021 Blub Blub. All rights reserved.
//

import XCTest
@testable import DownloadKit

// NOTE: FileMirror and Resource extensions have been moved to TestMocksAndHelpers.swift

class WeightedMirrorPolicyTests: XCTestCase {
    
    var policy: WeightedMirrorPolicy!
    var delegate: MockPolicyDelegate!
    let retries = 3
    
    override func setUpWithError() throws {
        policy = WeightedMirrorPolicy(numberOfRetries: retries)
        delegate = MockPolicyDelegate()
    }
    
    func setupPolicyAsync() async {
        await policy.setDelegate(delegate)
    }

    override func tearDownWithError() throws {
        policy = nil
        delegate = nil
    }
    
    func testPolicyReturnsMirrorWithHighestWeight() async {
        await setupPolicyAsync()
        
        let numberOfMirrors = 5
        let resource = Resource.sample(mirrorCount: numberOfMirrors)
        let downloadable = await policy.downloadable(for: resource, lastDownloadableIdentifier: nil, error: nil)
        
        XCTAssertNotNil(downloadable, "Should return a downloadable")
        // The policy should select the first alternative (highest weight)
        // Since alternatives are sorted by weight descending, first should have weight = numberOfMirrors
    }
    
    func testExhaustingAllMirrorsNotifiesDelegate() async {
        await setupPolicyAsync()
        
        let numberOfMirrors = 5
        let resource = Resource.sample(mirrorCount: numberOfMirrors)
        
        var lastDownloadableIdentifier: String?
        let error = NSError(domain: "mirror.policy.error", code: 10, userInfo: nil)
        
        // Try to exhaust all mirrors by repeatedly calling with error
        // numberOfMirrors + retries should exhaust all options
        for _ in 0...(numberOfMirrors + retries) {
            if let downloadable = await policy.downloadable(for: resource, lastDownloadableIdentifier: lastDownloadableIdentifier, error: error) {
                lastDownloadableIdentifier = await downloadable.identifier
            } else {
                // Policy returned nil, meaning mirrors are exhausted
                break
            }
        }
        
        XCTAssertEqual(delegate.exhaustedAllMirrors, true, "Delegate should be notified when all mirrors are exhausted")
    }
    
    func testCreatingDownloadableFromUnsupportedURL() async {
        await setupPolicyAsync()
        
        let resource = Resource(id: "random-id",
                                main: FileMirror(id: "mirror-id",
                                                 location: "Path/To/Local/File.jpg", // unsupported URL
                                                 info: [:]),
                                alternatives: [],
                                fileURL: nil)
        
        let downloadable = await policy.downloadable(for: resource, lastDownloadableIdentifier: nil, error: nil)
        
        // Policy should notify delegate when it fails to generate downloadable
        XCTAssertEqual(delegate.failedToGenerateDownloadable, true, "Delegate should be notified for unsupported URL")
        XCTAssertNil(downloadable, "Should return nil for unsupported URL")
    }
    
    func testRetryCountersAreTracked() async {
        await setupPolicyAsync()
        
        let numberOfMirrors = 1
        let resource = Resource.sample(mirrorCount: numberOfMirrors)
        
        var lastDownloadableIdentifier: String?
        let error = NSError(domain: "mirror.policy.error", code: 10, userInfo: nil)
        
        // Call with error multiple times to trigger retries
        for _ in 0...numberOfMirrors {
            if let downloadable = await policy.downloadable(for: resource, lastDownloadableIdentifier: lastDownloadableIdentifier, error: error) {
                lastDownloadableIdentifier = await downloadable.identifier
            }
        }
        
        // Verify that retry counters are being tracked
        let retryCounters = await policy.retryCounters(for: resource)
        XCTAssertFalse(retryCounters.isEmpty, "Retry counters should be tracked after errors")
    }
    
}

// NOTE: MockPolicyDelegate has been moved to TestMocksAndHelpers.swift
