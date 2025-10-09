//
//  AsyncPriorityQueue.swift
//  DownloadKit
//
//  Created by Dal Rupnik on 27.06.2025.
//

import Dispatch

public final class AsyncPriorityQueue<T : Sendable> : @unchecked Sendable {
    
    private let queue = DispatchQueue(label: "com.downloadkit.asyncpriorityqueue")
    fileprivate var heap = [T]()
    var order: (@Sendable (T, T) async -> Bool)?
    
    /// Creates a new PriorityQueue with the given ordering.
    ///
    /// - parameter order: A function that specifies whether its first argument should
    ///                    come after the second argument in the PriorityQueue.
    /// - parameter startingValues: An array of elements to initialize the PriorityQueue with.
    public init(order: @escaping @Sendable (T, T) async -> Bool) {
        self.order = order
    }
    
    public init() {
        
    }
    
    /// How many elements the Priority Queue stores
    public var count: Int { 
        return queue.sync { heap.count }
    }
    
    /// true if and only if the Priority Queue is empty
    public var isEmpty: Bool { 
        return queue.sync { heap.isEmpty }
    }
    
    /// Add a new element onto the Priority Queue. O(logn)
    ///
    /// - parameter element: The element to be inserted into the Priority Queue.
    public func enqueue(_ element: T) async {
        assert(order != nil, "PriorityQueue must be initialized with an ordering")
        
        // Get a snapshot for async comparison. The heap might change between
        // snapshot and insertion, so we clamp the index to valid range.
        // This trades perfect ordering for thread-safety in concurrent scenarios.
        let snapshot = queue.sync { heap }
        let index = await snapshot.insertionIndex { return await order!(element, $0) }
        
        queue.sync {
            // Clamp index to valid range - heap may have changed
            let safeIndex = Swift.min(index, heap.count)
            heap.insert(element, at: safeIndex)
        }
    }
    
    /// Remove and return the element with the highest priority (or lowest if ascending). O(lg n)
    ///
    /// - returns: The element with the highest priority in the Priority Queue, or nil if the PriorityQueue is empty.
    public func dequeue() -> T? {
        return queue.sync { () -> T? in
            if heap.isEmpty { return nil }
            
            return heap.removeLast()
        }
    }
    
    /// Get a look at the current highest priority item, without removing it. O(1)
    ///
    /// - returns: The element with the highest priority in the PriorityQueue, or nil if the PriorityQueue is empty.
    public func peek() -> T? {
        return queue.sync { heap.last }
    }
    
    /// Removes all elements matching condition
    /// - Parameter condition: to match
    public func remove(where condition: @escaping (T) async -> Bool) async {
        let currentHeap = queue.sync { heap }
        var newHeap: [T] = []

        for element in currentHeap {
            if await condition(element) == false {
                newHeap.append(element)
            }
        }

        queue.sync {
            heap = newHeap
        }
    }
    
    /// Eliminate all of the elements from the Priority Queue.
    public func clear() {
        queue.sync {
            heap.removeAll(keepingCapacity: false)
        }
    }
}

extension AsyncPriorityQueue where T: Equatable {
    /// Removes the first occurrence of a particular item. Finds it by value comparison using ==. O(n)
    /// Silently exits if no occurrence found.
    ///
    /// - parameter item: The item to remove the first occurrence of.
    public func remove(_ item: T) {
        queue.sync {
            if let index = heap.firstIndex(of: item) {
                heap.remove(at: index)
            }
        }
    }
    
    /// Removes all occurrences of a particular item. Finds it by value comparison using ==. O(n)
    /// Silently exits if no occurrence found.
    ///
    /// - parameter item: The item to remove.
    public func removeAll(_ item: T) {
        queue.sync {
            while let index = heap.firstIndex(of: item) {
                heap.remove(at: index)
            }
        }
    }
}

// MARK: - GeneratorType
extension AsyncPriorityQueue: IteratorProtocol {
    
    public typealias Element = T
    public func next() -> Element? { return dequeue() }
}

// MARK: - SequenceType
extension AsyncPriorityQueue: Sequence {
    
    public typealias Iterator = AsyncPriorityQueue
    public func makeIterator() -> Iterator { return self }
}

// MARK: - CollectionType
extension AsyncPriorityQueue: Collection {
    
    public typealias Index = Int
    
    public var startIndex: Int { 
        return queue.sync { heap.startIndex }
    }
    public var endIndex: Int { 
        return queue.sync { heap.endIndex }
    }
    
    public subscript(i: Int) -> T { 
        return queue.sync { heap[i] }
    }
    
    public func index(after i: AsyncPriorityQueue.Index) -> AsyncPriorityQueue.Index {
        return queue.sync { heap.index(after: i) }
    }
}

// MARK: - CustomStringConvertible, CustomDebugStringConvertible
extension AsyncPriorityQueue: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { 
        return queue.sync { heap.description }
    }
    public var debugDescription: String { 
        return queue.sync { heap.debugDescription }
    }
}

extension RandomAccessCollection {
    fileprivate func insertionIndex(for predicate: (Element) async -> Bool) async -> Index {
        var slice: SubSequence = self[...]
        
        while !slice.isEmpty {
            let middle = slice.index(slice.startIndex, offsetBy: slice.count / 2)
            if await predicate(slice[middle]) {
                slice = slice[index(after: middle)...]
            } else {
                slice = slice[..<middle]
            }
        }
        return slice.startIndex
    }
}
