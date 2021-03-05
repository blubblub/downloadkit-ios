//
//  ProgressNode.swift
//  BlubBlubCore
//
//  Created by Jure Lajlar on 31/10/2019.
//

import Foundation

public class ProgressNode {
    private let id = UUID().uuidString
    public let progress = Foundation.Progress()
    
    public var isCompleted: Bool {
        return progress.completedUnitCount == progress.totalUnitCount
    }
    
    public var isErrored: Bool {
        return error != nil
    }
    
    public var error: Error? {
        return items.first(where: { $0.error != nil })?.error
    }
    
    private var totalUnitCount: Int64 {
        return items.reduce(0, { $0 + $1.totalUnitCount })
    }
    
    private var completedUnitCount: Int64 {
        return items.reduce(0, { $0 + $1.completedUnitCount })
    }
    
    private let inBytes: Bool
    
    struct Item: Hashable {
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
    
    private var items = [Item]()
    
    init?(items: [String: Foundation.Progress], inBytes: Bool = true) {
        if items.count == 0 {
            return nil
        }
        
        self.inBytes = inBytes
        for (identifier, progress) in items {
            // For total unit count in bytes, add one, so it is not completed on byte count, but rather when complete method is called.
            let item = Item(identifier: identifier,
                            totalUnitCount: inBytes ? progress.totalUnitCount + 1 : 1,
                            completedUnitCount: inBytes ? progress.completedUnitCount : 0,
                            error: nil,
                            progress: progress)
            self.items.append(item)
        }
        
        self.progress.totalUnitCount = totalUnitCount
        self.progress.completedUnitCount = completedUnitCount
    }
    
    private init(items: [Item], inBytes: Bool) {
        self.inBytes = inBytes
        self.items = items
        self.progress.totalUnitCount = totalUnitCount
        self.progress.completedUnitCount = completedUnitCount
    }
    
    func retry(_ identifier: String, with progress: Foundation.Progress) {
        guard let index = items.firstIndex(where: { $0.identifier == identifier }) else {
            return
        }
        
        if items[index].completedUnitCount > 0 {
            return
        }
        
        items[index].error = nil
        items[index].completedUnitCount = 0
        items[index].totalUnitCount = inBytes ? progress.totalUnitCount + 1 : 1
        items[index].progress = progress
        
        self.progress.totalUnitCount = totalUnitCount
        self.progress.completedUnitCount = completedUnitCount
    }
    
    func complete(_ identifier: String, with error: Error? = nil) {
        guard let index = items.firstIndex(where: { $0.identifier == identifier }) else {
            return
        }
        
        items[index].error = error
        if error == nil {
            items[index].completedUnitCount = items[index].totalUnitCount
        }
        
        progress.completedUnitCount = completedUnitCount
    }
    
    /// Returns a new progress node adding any items that are in other node and updating
    /// existing values.
    func merge(with other: ProgressNode?) -> ProgressNode? {
        guard let other = other else { return self }
        // cannot merge if one is in bytes and other is not.
        guard self.inBytes == other.inBytes else { return nil }
        
        var items = self.items
        for index in items.indices {
            // if we have the same item in other node, change it
            if let otherItem = other.items.first(where: { $0 == items[index] }) {
                items[index].update(with: otherItem)
            }
        }
        // append missing items that are in other node, but not in self
        let missingIDs = Set(other.items.map { $0.identifier }).subtracting(items.map { $0.identifier })
        let missingItems = missingIDs.compactMap { id in other.items.first(where: { id == $0.identifier }) }
        items.append(contentsOf: missingItems)
        
        return ProgressNode(items: items, inBytes: inBytes)
    }
    
    func hasSameItems(as other: ProgressNode) -> Bool {
        return Set(items).isSuperset(of: other.items)
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
