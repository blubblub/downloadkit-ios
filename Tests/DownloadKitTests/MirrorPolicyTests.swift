//
//  WeightedMirrorPolicyTests.swift
//  BlubBlubCore_Tests
//
//  Created by Dal Rupnik on 2/18/21.
//  Copyright © 2021 Blub Blub. All rights reserved.
//

import XCTest
@testable import DownloadKit

class WeightedMirrorPolicyTests: XCTestCase {
    
    var policy: WeightedMirrorPolicy!
    var delegate: MockPolicyDelegate!
    let retries = 3
    
    override func setUpWithError() throws {
        policy = WeightedMirrorPolicy(numberOfRetries: retries)
        delegate = MockPolicyDelegate()
        policy.delegate = delegate
    }

    override func tearDownWithError() throws {
        policy = nil
        delegate = nil
    }
    
    func testPolicyReturnsMirrorWithHighestWeight() {
        let numberOfMirrors = 5
        let asset = Asset.sample(mirrorCount: numberOfMirrors)
        let selection = policy.mirror(for: asset, lastMirrorSelection: nil, error: nil)!
        
        XCTAssertEqual(selection.mirror.weight, numberOfMirrors)
    }
    
    func testExhaustingAllMirrorsNotifiesDelegate() {
        let numberOfMirrors = 5
        let asset = Asset.sample(mirrorCount: numberOfMirrors)
        
        var previousSelection: ResourceMirrorSelection?
        let error = NSError(domain: "mirror.policy.error", code: 10, userInfo: nil)
        
        for _ in 0...(numberOfMirrors + retries) {
            previousSelection = policy.mirror(for: asset, lastMirrorSelection: previousSelection, error: error)
        }
        
        XCTAssertEqual(delegate.exhaustedAllMirrors, true)
    }
    
    func testCreatingDownloadableFromUnsupportedURL() {
        let asset = Asset(id: "random-id",
                          main: FileMirror(id: "mirror-id",
                                           location: "Path/To/Local/File.jpg", // unsupported URL
                                           info: [:]),
                          alternatives: [],
                          fileURL: nil)
        
        _ = policy.mirror(for: asset, lastMirrorSelection: nil, error: nil)
        XCTAssertEqual(delegate.failedToGenerateDownloadable, true)
    }
    
    func testDownloadCompleteClearsRetryCount() {
        let numberOfMirrors = 1
        let asset = Asset.sample(mirrorCount: numberOfMirrors)
        
        var previousSelection: ResourceMirrorSelection?
        let error = NSError(domain: "mirror.policy.error", code: 10, userInfo: nil)
        for _ in 0...(numberOfMirrors) {
            previousSelection = policy.mirror(for: asset, lastMirrorSelection: previousSelection, error: error)
        }
        
        policy.downloadComplete(for: asset)
        
        XCTAssertEqual(policy.retryCounters(for: asset).isEmpty, true)
    }
    
}

class MockPolicyDelegate: MirrorPolicyDelegate {
    
    var exhaustedAllMirrors = false
    var failedToGenerateDownloadable = false
    
    func mirrorPolicy(_ mirrorPolicy: MirrorPolicy, didExhaustMirrorsIn file: ResourceFile) {
        exhaustedAllMirrors = true
    }
    
    func mirrorPolicy(_ mirrorPolicy: MirrorPolicy, didFailToGenerateDownloadableIn file: ResourceFile, for mirror: ResourceFileMirror) {
        failedToGenerateDownloadable = true
    }
}
