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
        let selection = await policy.mirror(for: resource, lastMirrorSelection: nil, error: nil)!
        
        XCTAssertEqual(selection.mirror.weight, numberOfMirrors)
    }
    
    func testExhaustingAllMirrorsNotifiesDelegate() async {
        await setupPolicyAsync()
        
        let numberOfMirrors = 5
        let resource = Resource.sample(mirrorCount: numberOfMirrors)
        
        var previousSelection: ResourceMirrorSelection?
        let error = NSError(domain: "mirror.policy.error", code: 10, userInfo: nil)
        
        for _ in 0...(numberOfMirrors + retries) {
            previousSelection = await policy.mirror(for: resource, lastMirrorSelection: previousSelection, error: error)
        }
        
        XCTAssertEqual(delegate.exhaustedAllMirrors, true)
    }
    
    func testCreatingDownloadableFromUnsupportedURL() async {
        await setupPolicyAsync()
        
        let resource = Resource(id: "random-id",
                                main: FileMirror(id: "mirror-id",
                                                 location: "Path/To/Local/File.jpg", // unsupported URL
                                                 info: [:]),
                                alternatives: [],
                                fileURL: nil)
        
        _ = await policy.mirror(for: resource, lastMirrorSelection: nil, error: nil)
        XCTAssertEqual(delegate.failedToGenerateDownloadable, true)
    }
    
    func testDownloadCompleteClearsRetryCount() async {
        await setupPolicyAsync()
        
        let numberOfMirrors = 1
        let resource = Resource.sample(mirrorCount: numberOfMirrors)
        
        var previousSelection: ResourceMirrorSelection?
        let error = NSError(domain: "mirror.policy.error", code: 10, userInfo: nil)
        for _ in 0...(numberOfMirrors) {
            previousSelection = await policy.mirror(for: resource, lastMirrorSelection: previousSelection, error: error)
        }
        
        await policy.downloadComplete(for: resource)
        
        let retryCounters = await policy.retryCounters(for: resource)
        XCTAssertEqual(retryCounters.isEmpty, true)
    }
    
}

// NOTE: MockPolicyDelegate has been moved to TestMocksAndHelpers.swift
