//
//  TestUtilities.swift
//  DownloadKitTests
//
//  Created by Dal Rupnik on 30.06.2025.
//

import Foundation

/// Thread-safe counter using actor for concurrency
actor ActorCounter {
    private var count = 0
    
    func increment() {
        count += 1
    }
    
    func setValue(_ newValue: Int) {
        count = newValue
    }
    
    var value: Int {
        count
    }
}

/// Thread-safe array using actor for concurrency
actor ActorArray<T> {
    private var items: [T] = []
    
    func append(_ item: T) {
        items.append(item)
    }
    
    var count: Int {
        items.count
    }
    
    var values: [T] {
        items
    }
}
