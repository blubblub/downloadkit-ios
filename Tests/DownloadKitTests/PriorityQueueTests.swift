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
    
    var queue: PriorityQueue<WebDownloadItem>!
    
    override func setUp() {
        super.setUp()
        
        queue = PriorityQueue<WebDownloadItem>(order: { $0.priority > $1.priority })
    }
    
    override func tearDown() {
        super.tearDown()
        
        queue = nil
    }
    
    func testPrioritySame() {
        let downloadItem1 = WebDownloadItem(identifier: "id1", url: URL(string: "https://google.com")!)
        queue.enqueue(downloadItem1)
        
        let downloadItem2 = WebDownloadItem(identifier: "id2", url: URL(string: "https://google.com")!)
        queue.enqueue(downloadItem2)
        
        let downloadItem3 = WebDownloadItem(identifier: "id3", url: URL(string: "https://google.com")!)
        queue.enqueue(downloadItem3)
        
        XCTAssertEqual(queue.peek()!.identifier, "id1")
        XCTAssertEqual(queue.dequeue()!.identifier, "id1")
        XCTAssertEqual(queue.dequeue()!.identifier, "id2")
        XCTAssertEqual(queue.dequeue()!.identifier, "id3")
    }

    func testPriorityHigherFirstTwoItems() {
        let downloadItem1 = WebDownloadItem(identifier: "id1", url: URL(string: "https://google.com")!)
        queue.enqueue(downloadItem1)
        
        let downloadItem2 = WebDownloadItem(identifier: "id2", url: URL(string: "https://google.com")!, priority: 1000)
        queue.enqueue(downloadItem2)

        XCTAssertEqual(queue.peek()!.identifier,"id2")
        XCTAssertEqual(queue.dequeue()!.identifier, "id2")
        XCTAssertEqual(queue.dequeue()!.identifier, "id1")
    }
    
    func testPriorityHigherFirst() {
        let downloadItem1 = WebDownloadItem(identifier: "id1", url: URL(string: "https://google.com")!)
        queue.enqueue(downloadItem1)
        
        let downloadItem2 = WebDownloadItem(identifier: "id2", url: URL(string: "https://google.com")!)
        queue.enqueue(downloadItem2)
        
        let downloadItem3 = WebDownloadItem(identifier: "id3", url: URL(string: "https://google.com")!, priority: 2)
        queue.enqueue(downloadItem3)
        
        XCTAssertEqual(queue.peek()!.identifier, "id3")
        XCTAssertEqual(queue.dequeue()!.identifier, "id3")
        XCTAssertEqual(queue.dequeue()!.identifier, "id1")
        XCTAssertEqual(queue.dequeue()!.identifier, "id2")
    }
    
    func testPriorityHigher() {
        let downloadItem1 = WebDownloadItem(identifier: "id1", url: URL(string: "https://google.com")!)
        queue.enqueue(downloadItem1)
        
        let downloadItem5 = WebDownloadItem(identifier: "id5", url: URL(string: "https://google.com")!)
        queue.enqueue(downloadItem5)
        
        let downloadItem2 = WebDownloadItem(identifier: "id2", url: URL(string: "https://google.com")!, priority: 2)
        queue.enqueue(downloadItem2)
        
        let downloadItem3 = WebDownloadItem(identifier: "id3", url: URL(string: "https://google.com")!, priority: 2)
        queue.enqueue(downloadItem3)
        
        let downloadItem4 = WebDownloadItem(identifier: "id4", url: URL(string: "https://google.com")!, priority: 2)
        queue.enqueue(downloadItem4)
        
        XCTAssertEqual(queue.peek()!.identifier, "id2")
        XCTAssertEqual(queue.dequeue()!.identifier, "id2")
        XCTAssertEqual(queue.dequeue()!.identifier, "id3")
        XCTAssertEqual(queue.dequeue()!.identifier, "id4")
        XCTAssertEqual(queue.dequeue()!.identifier, "id1")
        XCTAssertEqual(queue.dequeue()!.identifier, "id5")
    }
    
    func testPriorityHigherDifferent() {
        let downloadItem1 = WebDownloadItem(identifier: "id1", url: URL(string: "https://google.com")!)
        queue.enqueue(downloadItem1)
        
        let downloadItem5 = WebDownloadItem(identifier: "id5", url: URL(string: "https://google.com")!)
        queue.enqueue(downloadItem5)
        
        let downloadItem2 = WebDownloadItem(identifier: "id2", url: URL(string: "https://google.com")!, priority: 2)
        queue.enqueue(downloadItem2)
        
        let downloadItem3 = WebDownloadItem(identifier: "id3", url: URL(string: "https://google.com")!, priority: 2)
        queue.enqueue(downloadItem3)
        
        let downloadItem4 = WebDownloadItem(identifier: "id4", url: URL(string: "https://google.com")!, priority: 2)
        queue.enqueue(downloadItem4)
        
        let downloadItem6 = WebDownloadItem(identifier: "id6", url: URL(string: "https://google.com")!, priority: 5)
        queue.enqueue(downloadItem6)
        
        let downloadItem7 = WebDownloadItem(identifier: "id7", url: URL(string: "https://google.com")!, priority: 8)
        queue.enqueue(downloadItem7)
        
        let downloadItem8 = WebDownloadItem(identifier: "id8", url: URL(string: "https://google.com")!, priority: 5)
        queue.enqueue(downloadItem8)
        
        XCTAssertEqual(queue.peek()!.identifier, "id7")
        XCTAssertEqual(queue.dequeue()!.identifier, "id7")
        XCTAssertEqual(queue.dequeue()!.identifier, "id6")
        XCTAssertEqual(queue.dequeue()!.identifier, "id8")
        XCTAssertEqual(queue.dequeue()!.identifier, "id2")
        XCTAssertEqual(queue.dequeue()!.identifier, "id3")
        XCTAssertEqual(queue.dequeue()!.identifier, "id4")
        XCTAssertEqual(queue.dequeue()!.identifier, "id1")
        XCTAssertEqual(queue.dequeue()!.identifier, "id5")
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
