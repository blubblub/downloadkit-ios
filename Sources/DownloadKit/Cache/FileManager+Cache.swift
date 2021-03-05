//
//  FileManager+Cache.swift
//  DownloadKit
//
//  Created by Dal Rupnik on 2/11/21.
//

import Foundation

/// MARK: - File Manager Extensions
/// Convenience methods to generate local file URLs.
public extension FileManager {
    func generateLocalUrl(in directoryUrl: URL, for filename: String) -> URL? {
        var counter = 0
        var error = false
        
        var localFileUrl = directoryUrl.appendingPathComponent(filename)
        
        while fileExists(atPath: localFileUrl.path) && !error {
            localFileUrl = directoryUrl.appendingPathComponent(addCopyString(to: filename))
            
            if counter > 3 {
                error = true
            }
            
            counter += 1
        }
        
        return !error ? localFileUrl : nil
    }
    
    
    /// Adds copy string to filename as the prefix.
    /// Examples:
    /// - image.jpg will turn into copy-1.image.jpg
    /// - copy-1.image.jpg will turn into copy-2.image.jpg
    ///
    /// - Parameters:
    ///   - filename: filename to prefix
    ///   - prefix: prefix type, default `copy-`
    /// - Returns: Prefixed filename
    func addCopyString(to filename: String, with prefix: String = "copy-") -> String {
        var components = filename.components(separatedBy: ".")
        
        // Find our "(prefix)(n)" string, we just replace the number, it can be last or one before last.
        let index = components.count >= 2 ? components.count - 1 : 1
        
        if index < components.count && (components[index].hasPrefix(prefix) || components[index - 1].hasPrefix(prefix)) {
            let targetIndex = components[index].hasPrefix(prefix) ? index : index - 1
            
            let prefixValue = components[targetIndex].replacingOccurrences(of: prefix, with: "")
            
            if let number = Int(prefixValue) {
                components[targetIndex] = "\(prefix)\(number + 1)"
            }
            else {
                components[targetIndex] = "\(prefix)1"
            }
            
        }
        else {
            components.insert("\(prefix)1", at: index)
        }
        
        return components.joined(separator: ".")
    }
}
