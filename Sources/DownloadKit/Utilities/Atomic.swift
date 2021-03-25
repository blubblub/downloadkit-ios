//
//  Atomic.swift
//  
//
//  Created by Dal Rupnik on 2/17/21.
//

import Foundation
import os.lock

class AtomicDictionary<Key: Hashable, Value>: CustomDebugStringConvertible {
    private var store = [Key: Value]()
    
    private let queue = DispatchQueue(label: "org.blubblub.downloadkit.dict.\(UUID().uuidString)",
                                      qos: .utility,
                                      attributes: .concurrent)
    
    public init() {}
    
    public subscript(key: Key) -> Value? {
        get { queue.sync { store[key] }}
        set { queue.async(flags: .barrier) { [weak self] in self?.store[key] = newValue } }
    }
    
    var values: Dictionary<Key, Value>.Values {
        return queue.sync { store.values }
    }
    
    var count: Int {
        return queue.sync { store.count }
    }
    
    public var debugDescription: String {
        return store.debugDescription
    }
}
