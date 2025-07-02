//
//  Array+Sendable.swift
//  DownloadKit
//
//  Created by Dal Rupnik on 02.07.2025.
//

// MARK: - Extensions

extension Array {
    func unique(_ by: ((Element) -> String)) -> Array {
        var seen: [String: Bool] = [:]
        
        return self.filter { seen.updateValue(true, forKey: by($0)) == nil }
    }
}

extension Array where Element: Sendable {
    func filterAsync(_ transform: @escaping @Sendable (Element) async -> Bool) async -> [Element] {
        var finalResult = Array<Element>()
        
        for element in self {
            if await transform(element) {
                finalResult.append(element)
            }
        }
        
        return finalResult
    }
    
    func asyncContains(_ predicate: @escaping @Sendable (Element) async -> Bool) async -> Bool {
        for element in self {
            if await predicate(element) {
                return true
            }
        }
        return false
    }
}
