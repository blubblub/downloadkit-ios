//
//  Sequence+Extra.swift
//  DownloadKit
//
//  Created by Marcel Salej on 4. 5. 25.
//

import Foundation

extension Sequence {
    func asyncFirst(where predicate: @escaping (Element) async -> Bool) async -> Element? {
        for element in self {
            if await predicate(element) {
                return element
            }
        }
        return nil
    }
}
