//
//  ProgressNode.swift
//  BlubBlubCore
//
//  Created by Jure Lajlar on 31/10/2019.
//

import Foundation

final class SendableBox<T>: @unchecked Sendable {
    private let queue = DispatchQueue(label: "sendablebox.queue", attributes: .concurrent)
    private var _value: T
    
    init(_ value: T) {
        self._value = value
    }
    
    func read<U>(_ action: (T) -> U) -> U {
        return queue.sync {
            action(_value)
        }
    }
    
    func write<U>(_ action: (inout T) -> U) -> U {
        return queue.sync(flags: .barrier) {
            action(&_value)
        }
    }
}

public final class ProgressNode: Sendable {
    private let id = UUID().uuidString
    public let progress = Foundation.Progress()
    
    public var isCompleted: Bool {
        return progress.completedUnitCount == progress.totalUnitCount
    }
    
    public var isErrored: Bool {
        return error != nil
    }
    
    public var error: Error? {
        return _items.read { items in
            items.first(where: { $0.error != nil })?.error
        }
    }
    
    private var totalUnitCount: Int64 {
        return _items.read { items in
            items.reduce(0, { $0 + $1.totalUnitCount })
        }
    }
    
    private var completedUnitCount: Int64 {
        return _items.read { items in
            items.reduce(0, { $0 + $1.completedUnitCount })
        }
    }
    
    private let inBytes: Bool
    
    struct Item: Hashable, Sendable {
        let identifier: String
        var totalUnitCount: Int64
        var completedUnitCount: Int64
        var error: Error?
        var progress: Foundation.Progress
        
        mutating func update(with item: Item) {
            totalUnitCount = item.totalUnitCount
            completedUnitCount = item.completedUnitCount
            progress = item.progress
            error = item.error
        }
        
        static func == (lhs: ProgressNode.Item, rhs: ProgressNode.Item) -> Bool {
            return lhs.identifier == rhs.identifier
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(identifier)
        }
    }
    
    private let _items: SendableBox<[Item]>
    private let tasks: [String]
    
    public init?(tasks: [String], items: [String: Foundation.Progress], inBytes: Bool = true) {
        if items.count == 0 {
            return nil
        }
        
        self.tasks = tasks
        self.inBytes = inBytes
        var itemsArray: [Item] = []
        
        for (identifier, progress) in items {
            // For total unit count in bytes, add one, so it is not completed on byte count, but rather when complete method is called.
            let item = Item(identifier: identifier,
                            totalUnitCount: inBytes ? progress.totalUnitCount + 1 : 1,
                            completedUnitCount: inBytes ? progress.completedUnitCount : 0,
                            error: nil,
                            progress: progress)
            itemsArray.append(item)
        }
        
        self._items = SendableBox(itemsArray)
        
        // Calculate counts directly without using computed properties
        let totalCount = itemsArray.reduce(0, { $0 + $1.totalUnitCount })
        let completedCount = itemsArray.reduce(0, { $0 + $1.completedUnitCount })
        self.progress.totalUnitCount = totalCount
        self.progress.completedUnitCount = completedCount
    }
    
    private init(tasks: [String], items: [Item], inBytes: Bool) {
        self.tasks = tasks
        self.inBytes = inBytes
        self._items = SendableBox(items)
        // Calculate counts directly without using computed properties
        let totalCount = items.reduce(0, { $0 + $1.totalUnitCount })
        let completedCount = items.reduce(0, { $0 + $1.completedUnitCount })
        self.progress.totalUnitCount = totalCount
        self.progress.completedUnitCount = completedCount
    }
    
    public func retry(_ identifier: String, with progress: Foundation.Progress?) {
        guard let progress = progress else {
            return
        }
        
        let (newTotalUnitCount, newCompletedUnitCount) = _items.write { items in
            guard let index = items.firstIndex(where: { $0.identifier == identifier }) else {
                let totalCount = items.reduce(0, { $0 + $1.totalUnitCount })
                let completedCount = items.reduce(0, { $0 + $1.completedUnitCount })
                return (totalCount, completedCount)
            }
            
            if items[index].completedUnitCount > 0 {
                let totalCount = items.reduce(0, { $0 + $1.totalUnitCount })
                let completedCount = items.reduce(0, { $0 + $1.completedUnitCount })
                return (totalCount, completedCount)
            }
            
            items[index].error = nil
            items[index].completedUnitCount = 0
            items[index].totalUnitCount = inBytes ? progress.totalUnitCount + 1 : 1
            items[index].progress = progress
            
            let totalCount = items.reduce(0, { $0 + $1.totalUnitCount })
            let completedCount = items.reduce(0, { $0 + $1.completedUnitCount })
            return (totalCount, completedCount)
        }
        
        // Update progress synchronously
        self.progress.totalUnitCount = newTotalUnitCount
        self.progress.completedUnitCount = newCompletedUnitCount
    }
    
    public func complete(_ identifier: String, with error: Error? = nil) {
        let newCompletedUnitCount = _items.write { items in
            guard let index = items.firstIndex(where: { $0.identifier == identifier }) else {
                return items.reduce(0, { $0 + $1.completedUnitCount })
            }
            
            items[index].error = error
            if error == nil {
                items[index].completedUnitCount = items[index].totalUnitCount
            }
            
            return items.reduce(0, { $0 + $1.completedUnitCount })
        }
        
        // Update progress synchronously
        self.progress.completedUnitCount = newCompletedUnitCount
    }
    
    private func getItems() -> [Item] {
        return _items.read { $0 }
    }
    
    /// Returns a new progress node adding any items that are in other node and updating
    /// existing values.
    public func merge(with other: ProgressNode?) -> ProgressNode? {
        guard let other = other else { return self }
        // cannot merge if one is in bytes and other is not.
        guard self.inBytes == other.inBytes else { return nil }
        
        // Get items from both nodes separately to avoid deadlocks
        let selfItems = self.getItems()
        let otherItems = other.getItems()
        
        var items = selfItems
        for index in items.indices {
            // if we have the same item in other node, change it
            if let otherItem = otherItems.first(where: { $0 == items[index] }) {
                items[index].update(with: otherItem)
            }
        }
        // append missing items that are in other node, but not in self
        let missingIDs = Set(otherItems.map { $0.identifier }).subtracting(items.map { $0.identifier })
        let missingItems = missingIDs.compactMap { id in otherItems.first(where: { id == $0.identifier }) }
        items.append(contentsOf: missingItems)
        
        let mergedTasks = Set(tasks).union(other.tasks)
        
        return ProgressNode(tasks: Array(mergedTasks), items: items, inBytes: inBytes)
    }
    
    public func hasSameItems(as other: ProgressNode) -> Bool {
        // Get items from both nodes separately to avoid deadlocks
        let selfItems = self.getItems()
        let otherItems = other.getItems()
        return Set(selfItems).isSuperset(of: otherItems)
    }
}

extension ProgressNode: Equatable {
    public static func == (lhs: ProgressNode, rhs: ProgressNode) -> Bool {
        return lhs.id == rhs.id
    }
}

extension ProgressNode: CustomDebugStringConvertible {
    public var debugDescription: String {
        return id
    }
}
