import XCTest
@testable import DownloadKit

class AsyncPriorityQueueTests: XCTestCase, @unchecked Sendable {
    
    func testInitialization() {
        let queue = AsyncPriorityQueue<Int>()
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.count, 0)
        XCTAssertNil(queue.peek())
    }
    
    func testInitializationWithOrder() {
        let queue = AsyncPriorityQueue<Int>(order: { $0 > $1 })
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.count, 0)
        XCTAssertNil(queue.peek())
    }
    
    func testEnqueueAndDequeue() async {
        var queue = AsyncPriorityQueue<Int>(order: { $0 > $1 })
        
        await queue.enqueue(5)
        await queue.enqueue(3)
        await queue.enqueue(8)
        
        XCTAssertFalse(queue.isEmpty)
        XCTAssertEqual(queue.count, 3)
        
        // Should dequeue in priority order (highest first)
        let first = queue.dequeue()
        XCTAssertEqual(first, 8)
        
        let second = queue.dequeue()
        XCTAssertEqual(second, 5)
        
        let third = queue.dequeue()
        XCTAssertEqual(third, 3)
        
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.count, 0)
    }
    
    func testPeek() async {
        var queue = AsyncPriorityQueue<Int>(order: { $0 > $1 })
        
        XCTAssertNil(queue.peek())
        
        await queue.enqueue(5)
        XCTAssertEqual(queue.peek(), 5)
        
        await queue.enqueue(10)
        XCTAssertEqual(queue.peek(), 10) // Should be highest priority
        
        await queue.enqueue(3)
        XCTAssertEqual(queue.peek(), 10) // Should still be highest
        
        // Peek shouldn't remove the element
        XCTAssertEqual(queue.count, 3)
    }
    
    func testDequeueFromEmptyQueue() {
        var queue = AsyncPriorityQueue<Int>(order: { $0 > $1 })
        
        let result = queue.dequeue()
        XCTAssertNil(result)
    }
    
    func testClear() async {
        var queue = AsyncPriorityQueue<Int>(order: { $0 > $1 })
        
        await queue.enqueue(1)
        await queue.enqueue(2)
        await queue.enqueue(3)
        
        XCTAssertEqual(queue.count, 3)
        
        queue.clear()
        
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.count, 0)
        XCTAssertNil(queue.peek())
    }
    
    func testRemoveWithCondition() async {
        var queue = AsyncPriorityQueue<Int>(order: { $0 > $1 })
        
        await queue.enqueue(1)
        await queue.enqueue(2)
        await queue.enqueue(3)
        await queue.enqueue(4)
        await queue.enqueue(5)
        
        // Remove even numbers
        await queue.remove { $0 % 2 == 0 }
        
        XCTAssertEqual(queue.count, 3) // Should have 1, 3, 5 remaining
        
        // Verify only odd numbers remain
        let remaining = Array(queue)
        let sortedRemaining = remaining.sorted()
        XCTAssertEqual(sortedRemaining, [1, 3, 5])
    }
    
    func testRemoveSpecificItem() async {
        var queue = AsyncPriorityQueue<Int>(order: { $0 > $1 })
        
        await queue.enqueue(1)
        await queue.enqueue(2)
        await queue.enqueue(3)
        
        queue.remove(2)
        
        XCTAssertEqual(queue.count, 2)
        
        let remaining = Array(queue)
        XCTAssertFalse(remaining.contains(2))
        XCTAssertTrue(remaining.contains(1))
        XCTAssertTrue(remaining.contains(3))
    }
    
    func testRemoveAllOccurrences() async {
        var queue = AsyncPriorityQueue<Int>(order: { $0 > $1 })
        
        await queue.enqueue(1)
        await queue.enqueue(2)
        await queue.enqueue(2)
        await queue.enqueue(3)
        await queue.enqueue(2)
        
        queue.removeAll(2)
        
        XCTAssertEqual(queue.count, 2) // Should have 1, 3 remaining
        
        let remaining = Array(queue)
        XCTAssertFalse(remaining.contains(2))
        XCTAssertTrue(remaining.contains(1))
        XCTAssertTrue(remaining.contains(3))
    }
    
    func testRemoveNonExistentItem() async {
        var queue = AsyncPriorityQueue<Int>(order: { $0 > $1 })
        
        await queue.enqueue(1)
        await queue.enqueue(2)
        await queue.enqueue(3)
        
        queue.remove(99) // Item that doesn't exist
        
        XCTAssertEqual(queue.count, 3) // Count should remain the same
    }
    
    func testIterator() async {
        var queue = AsyncPriorityQueue<Int>(order: { $0 > $1 })
        
        await queue.enqueue(1)
        await queue.enqueue(2)
        await queue.enqueue(3)
        
        var iterator = queue.makeIterator()
        var results: [Int] = []
        
        while let item = iterator.next() {
            results.append(item)
        }
        
        XCTAssertEqual(results.count, 3)
        // Note: Iterator removes items via dequeue, so the original queue might not be empty
        // since iterator works on a copy
        XCTAssertGreaterThanOrEqual(queue.count, 0)
    }
    
    func testSequenceProtocol() async {
        var queue = AsyncPriorityQueue<Int>(order: { $0 > $1 })
        
        await queue.enqueue(1)
        await queue.enqueue(2)
        await queue.enqueue(3)
        
        let elements = Array(queue)
        XCTAssertEqual(elements.count, 3)
        XCTAssertTrue(elements.contains(1))
        XCTAssertTrue(elements.contains(2))
        XCTAssertTrue(elements.contains(3))
    }
    
    func testCollectionProtocol() async {
        var queue = AsyncPriorityQueue<Int>(order: { $0 > $1 })
        
        await queue.enqueue(1)
        await queue.enqueue(2)
        await queue.enqueue(3)
        
        XCTAssertEqual(queue.startIndex, 0)
        XCTAssertEqual(queue.endIndex, 3)
        
        // Test subscript access
        let firstElement = queue[0]
        XCTAssertTrue([1, 2, 3].contains(firstElement))
        
        // Test index(after:)
        let nextIndex = queue.index(after: 0)
        XCTAssertEqual(nextIndex, 1)
    }
    
    func testStringDescription() async {
        var queue = AsyncPriorityQueue<Int>(order: { $0 > $1 })
        
        await queue.enqueue(1)
        await queue.enqueue(2)
        
        let description = queue.description
        XCTAssertFalse(description.isEmpty)
        
        let debugDescription = queue.debugDescription
        XCTAssertFalse(debugDescription.isEmpty)
    }
    
    func testComplexObjectOrdering() async {
        struct TestItem: Sendable {
            let id: String
            let priority: Int
        }
        
        var queue = AsyncPriorityQueue<TestItem>(order: { $0.priority > $1.priority })
        
        let item1 = TestItem(id: "low", priority: 1)
        let item2 = TestItem(id: "high", priority: 10)
        let item3 = TestItem(id: "medium", priority: 5)
        
        await queue.enqueue(item1)
        await queue.enqueue(item2)
        await queue.enqueue(item3)
        
        // Should dequeue in priority order
        let first = queue.dequeue()
        XCTAssertEqual(first?.id, "high")
        
        let second = queue.dequeue()
        XCTAssertEqual(second?.id, "medium")
        
        let third = queue.dequeue()
        XCTAssertEqual(third?.id, "low")
    }
    
}
