//
//  PriorityQueueTests.swift
//  BlubBlubCore_Tests
//
//  Created by Dal Rupnik on 12/19/17.
//  Copyright © 2017 Blub Blub. All rights reserved.
//

import XCTest
import DownloadKit

class PriorityQueueTests: XCTestCase {
    
    var queue: AsyncPriorityQueue<WebDownload>!
    
    override func setUp() {
        super.setUp()
        
        queue = AsyncPriorityQueue<WebDownload>(order: { (lhs: WebDownload, rhs: WebDownload) in
            let lhsPriority = await lhs.priority
            let rhsPriority = await rhs.priority
            return lhsPriority > rhsPriority
        })
    }
    
    override func tearDown() {
        super.tearDown()
        
        queue = nil
    }
    
    func testPrioritySame() async {
        let downloadItem1 = WebDownload(identifier: "id1", url: URL(string: "https://google.com")!)
        await queue.enqueue(downloadItem1)
        
        let downloadItem2 = WebDownload(identifier: "id2", url: URL(string: "https://google.com")!)
        await queue.enqueue(downloadItem2)
        
        let downloadItem3 = WebDownload(identifier: "id3", url: URL(string: "https://google.com")!)
        await queue.enqueue(downloadItem3)
        
        let peekItem = queue.peek()!
        let peekIdentifier = await peekItem.identifier
        XCTAssertEqual(peekIdentifier, "id1")
        
        let item1 = queue.dequeue()!
        let item1Identifier = await item1.identifier
        XCTAssertEqual(item1Identifier, "id1")
        
        let item2 = queue.dequeue()!
        let item2Identifier = await item2.identifier
        XCTAssertEqual(item2Identifier, "id2")
        
        let item3 = queue.dequeue()!
        let item3Identifier = await item3.identifier
        XCTAssertEqual(item3Identifier, "id3")
    }

    func testPriorityHigherFirstTwoItems() async {
        let downloadItem1 = WebDownload(identifier: "id1", url: URL(string: "https://google.com")!)
        await queue.enqueue(downloadItem1)
        
        let downloadItem2 = WebDownload(identifier: "id2", url: URL(string: "https://google.com")!, priority: 1000)
        await queue.enqueue(downloadItem2)

        let peekItem = queue.peek()!
        let peekIdentifier = await peekItem.identifier
        XCTAssertEqual(peekIdentifier, "id2")
        
        let item1 = queue.dequeue()!
        let item1Identifier = await item1.identifier
        XCTAssertEqual(item1Identifier, "id2")
        
        let item2 = queue.dequeue()!
        let item2Identifier = await item2.identifier
        XCTAssertEqual(item2Identifier, "id1")
    }
    
    func testPriorityHigherFirst() async {
        let downloadItem1 = WebDownload(identifier: "id1", url: URL(string: "https://google.com")!)
        await queue.enqueue(downloadItem1)
        
        let downloadItem2 = WebDownload(identifier: "id2", url: URL(string: "https://google.com")!)
        await queue.enqueue(downloadItem2)
        
        let downloadItem3 = WebDownload(identifier: "id3", url: URL(string: "https://google.com")!, priority: 2)
        await queue.enqueue(downloadItem3)
        
        let peekItem = queue.peek()!
        let peekIdentifier = await peekItem.identifier
        XCTAssertEqual(peekIdentifier, "id3")
        
        let item1 = queue.dequeue()!
        let item1Identifier = await item1.identifier
        XCTAssertEqual(item1Identifier, "id3")
        
        let item2 = queue.dequeue()!
        let item2Identifier = await item2.identifier
        XCTAssertEqual(item2Identifier, "id1")
        
        let item3 = queue.dequeue()!
        let item3Identifier = await item3.identifier
        XCTAssertEqual(item3Identifier, "id2")
    }
    
    func testPriorityHigher() async {
        let downloadItem1 = WebDownload(identifier: "id1", url: URL(string: "https://google.com")!)
        await queue.enqueue(downloadItem1)
        
        let downloadItem5 = WebDownload(identifier: "id5", url: URL(string: "https://google.com")!)
        await queue.enqueue(downloadItem5)
        
        let downloadItem2 = WebDownload(identifier: "id2", url: URL(string: "https://google.com")!, priority: 2)
        await queue.enqueue(downloadItem2)
        
        let downloadItem3 = WebDownload(identifier: "id3", url: URL(string: "https://google.com")!, priority: 2)
        await queue.enqueue(downloadItem3)
        
        let downloadItem4 = WebDownload(identifier: "id4", url: URL(string: "https://google.com")!, priority: 2)
        await queue.enqueue(downloadItem4)
        
        let peekItem = queue.peek()!
        let peekIdentifier = await peekItem.identifier
        XCTAssertEqual(peekIdentifier, "id2")
        
        let item1 = queue.dequeue()!
        let item1Identifier = await item1.identifier
        XCTAssertEqual(item1Identifier, "id2")
        
        let item2 = queue.dequeue()!
        let item2Identifier = await item2.identifier
        XCTAssertEqual(item2Identifier, "id3")
        
        let item3 = queue.dequeue()!
        let item3Identifier = await item3.identifier
        XCTAssertEqual(item3Identifier, "id4")
        
        let item4 = queue.dequeue()!
        let item4Identifier = await item4.identifier
        XCTAssertEqual(item4Identifier, "id1")
        
        let item5 = queue.dequeue()!
        let item5Identifier = await item5.identifier
        XCTAssertEqual(item5Identifier, "id5")
    }
    
    func testPriorityHigherDifferent() async {
        let downloadItem1 = WebDownload(identifier: "id1", url: URL(string: "https://google.com")!)
        await queue.enqueue(downloadItem1)
        
        let downloadItem5 = WebDownload(identifier: "id5", url: URL(string: "https://google.com")!)
        await queue.enqueue(downloadItem5)
        
        let downloadItem2 = WebDownload(identifier: "id2", url: URL(string: "https://google.com")!, priority: 2)
        await queue.enqueue(downloadItem2)
        
        let downloadItem3 = WebDownload(identifier: "id3", url: URL(string: "https://google.com")!, priority: 2)
        await queue.enqueue(downloadItem3)
        
        let downloadItem4 = WebDownload(identifier: "id4", url: URL(string: "https://google.com")!, priority: 2)
        await queue.enqueue(downloadItem4)
        
        let downloadItem6 = WebDownload(identifier: "id6", url: URL(string: "https://google.com")!, priority: 5)
        await queue.enqueue(downloadItem6)
        
        let downloadItem7 = WebDownload(identifier: "id7", url: URL(string: "https://google.com")!, priority: 8)
        await queue.enqueue(downloadItem7)
        
        let downloadItem8 = WebDownload(identifier: "id8", url: URL(string: "https://google.com")!, priority: 5)
        await queue.enqueue(downloadItem8)
        
        let peekItem = queue.peek()!
        let peekIdentifier = await peekItem.identifier
        XCTAssertEqual(peekIdentifier, "id7")
        
        let item1 = queue.dequeue()!
        let item1Identifier = await item1.identifier
        XCTAssertEqual(item1Identifier, "id7")
        
        let item2 = queue.dequeue()!
        let item2Identifier = await item2.identifier
        XCTAssertEqual(item2Identifier, "id6")
        
        let item3 = queue.dequeue()!
        let item3Identifier = await item3.identifier
        XCTAssertEqual(item3Identifier, "id8")
        
        let item4 = queue.dequeue()!
        let item4Identifier = await item4.identifier
        XCTAssertEqual(item4Identifier, "id2")
        
        let item5 = queue.dequeue()!
        let item5Identifier = await item5.identifier
        XCTAssertEqual(item5Identifier, "id3")
        
        let item6 = queue.dequeue()!
        let item6Identifier = await item6.identifier
        XCTAssertEqual(item6Identifier, "id4")
        
        let item7 = queue.dequeue()!
        let item7Identifier = await item7.identifier
        XCTAssertEqual(item7Identifier, "id1")
        
        let item8 = queue.dequeue()!
        let item8Identifier = await item8.identifier
        XCTAssertEqual(item8Identifier, "id5")
    }
    
    @available(iOS 13.0, *)
    func testEnqueuePerformance() {
        let limit = 3000
        var queue = PriorityQueue<Int>(order: >)
        measure(metrics: [XCTCPUMetric(),
                          XCTClockMetric()]) {
            for _ in 0...limit { queue.enqueue(0) }
        }
    }
    
    @available(iOS 13.0, *)
    func testDequeuePerformance() {
        let limit = 3000
        var queue = PriorityQueue<Int>(order: >)
        for _ in 0...limit { queue.enqueue(0) }
        
        measure(metrics: [XCTCPUMetric(),
                          XCTClockMetric()]) {
            for _ in 0...limit { _ = queue.dequeue() }
        }
    }
    
}
