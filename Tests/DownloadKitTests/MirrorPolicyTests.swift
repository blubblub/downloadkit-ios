//
//  WeightedMirrorPolicyTests.swift
//  BlubBlubCore_Tests
//
//  Created by Dal Rupnik on 2/18/21.
//  Copyright © 2021 Blub Blub. All rights reserved.
//

import XCTest
import DownloadKit

class WeightedMirrorPolicyTests: XCTestCase {
    
    var policy: WeightedMirrorPolicy?
    
    override func setUpWithError() throws {
        policy = WeightedMirrorPolicy()
    }

    override func tearDownWithError() throws {
        policy = nil
    }

    func testCanProcess() throws {
    }
}
