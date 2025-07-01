//
//  AsyncPriorityQueue.swift
//  DownloadKit
//
//  Created by Dal Rupnik on 27.06.2025.
//

public struct AsyncPriorityQueue<T : Sendable> : Sendable {
    
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
    public var count: Int { return heap.count }
    
    /// true if and only if the Priority Queue is empty
    public var isEmpty: Bool { return heap.isEmpty }
    
    /// Add a new element onto the Priority Queue. O(logn)
    ///
    /// - parameter element: The element to be inserted into the Priority Queue.
    public mutating func enqueue(_ element: T) async {
        assert(order != nil, "PriorityQueue must be initialized with an ordering")
        
        let index = await heap.insertionIndex { return await order!(element, $0) }
        heap.insert(element, at: index)
    }
    
    /// Remove and return the element with the highest priority (or lowest if ascending). O(lg n)
    ///
    /// - returns: The element with the highest priority in the Priority Queue, or nil if the PriorityQueue is empty.
    public mutating func dequeue() -> T? {
        
        if heap.isEmpty { return nil }
        
        return heap.removeLast()
    }
    
    /// Get a look at the current highest priority item, without removing it. O(1)
    ///
    /// - returns: The element with the highest priority in the PriorityQueue, or nil if the PriorityQueue is empty.
    public func peek() -> T? {
        return heap.last
    }
    
    /// Removes all elements matching condition
    /// - Parameter condition: to match
    public mutating func remove(where condition: @escaping (T) async -> Bool) async {
        var newHeap: [T] = []

        for element in heap {
            if await condition(element) == false {
                newHeap.append(element)
            }
        }

        heap = newHeap
    }
    
    /// Eliminate all of the elements from the Priority Queue.
    public mutating func clear() {
        heap.removeAll(keepingCapacity: false)
    }
}

extension AsyncPriorityQueue where T: Equatable {
    /// Removes the first occurrence of a particular item. Finds it by value comparison using ==. O(n)
    /// Silently exits if no occurrence found.
    ///
    /// - parameter item: The item to remove the first occurrence of.
    public mutating func remove(_ item: T) {
        if let index = heap.firstIndex(of: item) {
            heap.remove(at: index)
        }
    }
    
    /// Removes all occurrences of a particular item. Finds it by value comparison using ==. O(n)
    /// Silently exits if no occurrence found.
    ///
    /// - parameter item: The item to remove.
    public mutating func removeAll(_ item: T) {
        while let index = heap.firstIndex(of: item) {
            heap.remove(at: index)
        }
    }
}

// MARK: - GeneratorType
extension AsyncPriorityQueue: IteratorProtocol {
    
    public typealias Element = T
    mutating public func next() -> Element? { return dequeue() }
}

// MARK: - SequenceType
extension AsyncPriorityQueue: Sequence {
    
    public typealias Iterator = AsyncPriorityQueue
    public func makeIterator() -> Iterator { return self }
}

// MARK: - CollectionType
extension AsyncPriorityQueue: Collection {
    
    public typealias Index = Int
    
    public var startIndex: Int { return heap.startIndex }
    public var endIndex: Int { return heap.endIndex }
    
    public subscript(i: Int) -> T { return heap[i] }
    
    public func index(after i: AsyncPriorityQueue.Index) -> AsyncPriorityQueue.Index {
        return heap.index(after: i)
    }
}

// MARK: - CustomStringConvertible, CustomDebugStringConvertible
extension AsyncPriorityQueue: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { return heap.description }
    public var debugDescription: String { return heap.debugDescription }
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
