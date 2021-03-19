//
//  Atomic.swift
//  
//
//  Created by Dal Rupnik on 2/17/21.
//

import Foundation
import os.lock

/// An `os_unfair_lock` wrapper.
final class UnfairLock {
    private let unfairLock: os_unfair_lock_t

    init() {
        unfairLock = .allocate(capacity: 1)
        unfairLock.initialize(to: os_unfair_lock())
    }

    deinit {
        unfairLock.deinitialize(count: 1)
        unfairLock.deallocate()
    }

    private func lock() {
        os_unfair_lock_lock(unfairLock)
    }

    private func unlock() {
        os_unfair_lock_unlock(unfairLock)
    }

    /// Executes a closure returning a value while acquiring the lock.
    ///
    /// - Parameter closure: The closure to run.
    ///
    /// - Returns:           The value the closure generated.
    func around<T>(_ closure: () -> T) -> T {
        lock(); defer { unlock() }
        return closure()
    }

    /// Execute a closure while acquiring the lock.
    ///
    /// - Parameter closure: The closure to run.
    func around(_ closure: () -> Void) {
        lock(); defer { unlock() }
        return closure()
    }
}

class Synchronized<Wrapped> {
    private var data: Wrapped
    private var lock: UnfairLock
    
    init(data: Wrapped, lock: UnfairLock = UnfairLock()) {
        self.data = data
        self.lock = lock
    }
    
    func sync<T>(_ body: (inout Wrapped) -> T) -> T {
        return self.lock.around { body(&self.data) }
    }
}

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
