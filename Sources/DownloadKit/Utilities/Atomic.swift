//
//  Atomic.swift
//  
//
//  Created by Dal Rupnik on 2/17/21.
//

import Foundation

@propertyWrapper
struct Atomic<Value> {

    private let lock = DispatchSemaphore(value: 1)
    private var value: Value

    init(wrappedValue: Value) {
        self.value = wrappedValue
    }

    var wrappedValue: Value {
        get {
            lock.wait()
            defer { lock.signal() }
            return value
        }
        set {
            lock.wait()
            value = newValue
            lock.signal()
        }
    }
}
