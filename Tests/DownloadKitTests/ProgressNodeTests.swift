//
//  ProgressNodeTests.swift
//  BlubBlubCore_Tests
//
//  Created by Dal Rupnik on 12/22/17.
//  Copyright © 2017 Blub Blub. All rights reserved.
//

import XCTest
import DownloadKit

class ProgressNodeTests: XCTestCase {
    
    private var node: ProgressNode!
    private var nodeWithoutBytes: ProgressNode!
    private let items = [
        "id1" : Foundation.Progress(totalUnitCount: 50),
        "id2" : Foundation.Progress(totalUnitCount: 150),
        "id3" : Foundation.Progress(totalUnitCount: 200),
        "id4" : Foundation.Progress(totalUnitCount: 250),
        "id5" : Foundation.Progress(totalUnitCount: 80),
        "id6" : Foundation.Progress(totalUnitCount: 150),
        "id7" : Foundation.Progress(totalUnitCount: 76)
    ]
    
    var totalUnitCount: Int64 {
        items.reduce(0, { $0 + $1.value.totalUnitCount }) + Int64(items.count)
    }
    
    override func setUp() {
        super.setUp()
        node = ProgressNode(tasks: Array(items.keys), items: items)
        nodeWithoutBytes = ProgressNode(tasks: Array(items.keys), items: items, inBytes: false)
    }
    
    override func tearDown() {
        super.tearDown()
        
        node = nil
        nodeWithoutBytes = nil
    }
    
    func testProgressPercent() {
        XCTAssertEqual(node.progress.totalUnitCount, totalUnitCount)
        
        node.complete("id1") // 50 + 1 completed
        XCTAssertEqual(node.progress.completedUnitCount, 51)
        
        node.complete("id6") // 51 + 150 + 1 completed
        XCTAssertEqual(node.progress.completedUnitCount, 202)
    }
    
    func testProgressPercentWithoutBytes() {
        XCTAssertEqual(nodeWithoutBytes.progress.totalUnitCount, Int64(items.count))
        
        nodeWithoutBytes.complete("id1")
        XCTAssertEqual(nodeWithoutBytes.progress.completedUnitCount, 1)
        
        nodeWithoutBytes.complete("id6")
        XCTAssertEqual(nodeWithoutBytes.progress.completedUnitCount, 2)
    }
    
    func testProgressComplete() {
        for (key, _) in items {
            node.complete(key)
        }
        
        XCTAssertEqual(node.progress.completedUnitCount, totalUnitCount)
        XCTAssertTrue(node.isCompleted)
    }
    
    func testProgressCompleteWithoutBytes() {
        for (key, _) in items {
            nodeWithoutBytes.complete(key)
        }
        
        XCTAssertEqual(nodeWithoutBytes.progress.completedUnitCount, Int64(items.count))
        XCTAssertTrue(nodeWithoutBytes.isCompleted)
    }
    
    func testProgressErrored() {
        node.complete("id4", with: NSError(domain: "org.blubbblub.core.testing", code: -33, userInfo: nil))
        
        XCTAssertTrue(node.isErrored)
        XCTAssertNotNil(node.error)
    }
    
    func testProgressRetry() {
        node.complete("id4", with: NSError(domain: "org.blubbblub.core.testing", code: -33, userInfo: nil))
        
        XCTAssertTrue(node.isErrored)
        XCTAssertNotNil(node.error)
        
        node.retry("id4", with: items["id4"]!)
        
        XCTAssertFalse(node.isErrored)
        XCTAssertFalse(node.isCompleted)
    }
    
    func testProgressRetryAndComplete() {
        node.complete("id1", with: nil)
        node.complete("id2", with: nil)
        node.complete("id3", with: nil)
        node.complete("id4", with: NSError(domain: "org.blubbblub.core.testing", code: -33, userInfo: nil))
        node.complete("id5", with: nil)
        node.complete("id6", with: nil)
        node.complete("id7", with: nil)
        
        XCTAssertTrue(node.isErrored)
        XCTAssertFalse(node.isCompleted)
        XCTAssertNotNil(node.error)
        
        node.retry("id4", with: items["id4"]!)
        
        XCTAssertFalse(node.isErrored)
        XCTAssertFalse(node.isCompleted)
        
        node.complete("id4", with: nil)
        
        XCTAssertFalse(node.isErrored)
        XCTAssertTrue(node.isCompleted)
    }
    
    func testCompletingSameItemMultipleTimes() {
        node.complete("id4")
        node.complete("id4")
        node.complete("id4")
        node.complete("id4")
        
        XCTAssertEqual(node.progress.completedUnitCount, items["id4"]!.totalUnitCount + 1)
    }
    
    func testRetryAfterCompletingItem() {
        node.complete("id4")
        node.retry("id4", with: items["id4"]!)
        
        // if it's completed, retry does nothing
        XCTAssertEqual(node.progress.completedUnitCount, items["id4"]!.totalUnitCount + 1)
    }
    
    func testInitializingWithEmptyItemsList() {
        node = ProgressNode(tasks: [], items: [:])
        XCTAssertNil(node)
    }
    
    func testMergingTwoProgressNodes() {
        let other = ProgressNode(tasks: ["id100"], items: ["id100" : Foundation.Progress(totalUnitCount: 10)])!
        
        node.complete("id1")
        node.complete("id2")
        
        let merged = node.merge(with: other)!
        
        XCTAssertEqual(merged.progress.completedUnitCount, 202)
        XCTAssertEqual(merged.progress.totalUnitCount, totalUnitCount + other.progress.totalUnitCount)
        
        let mergedWithNil = node.merge(with: nil)
        XCTAssertEqual(mergedWithNil, node)
        
        let nodeWithoutBytes = ProgressNode(tasks: ["abc"], items: ["abc" : Foundation.Progress(totalUnitCount: 10)], inBytes: false)
        XCTAssertNil(nodeWithoutBytes?.merge(with: node))
    }
    
    func testCompletingItemNotContainedInNode() {
        node.complete("random")
        node.complete("jdfsjknsdf")
        
        XCTAssertEqual(node.progress.completedUnitCount, 0)
    }
    
    func testEquality() {
        let other = ProgressNode(tasks: Array(items.keys), items: items)
        XCTAssertTrue(other!.hasSameItems(as: node))
    }
}
