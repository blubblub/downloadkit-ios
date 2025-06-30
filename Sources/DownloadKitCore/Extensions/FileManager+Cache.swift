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
        let expression = NSRegularExpression(prefix + "(\\d+)")
        let range = NSRange(location: 0, length: filename.utf16.count)
        
        var count = 1
        
        var newFileName = filename
        // if a match is found, we increment the count number
        if let match = expression.firstMatch(in: filename, options: [], range: range),
           let countRange = Range<String.Index>(match.range(at: 1), in: filename) {
            count = (Int(filename[countRange]) ?? 0) + 1
            newFileName = String(filename[countRange.upperBound...].dropFirst())
        }
        
        
        return "\(prefix)\(count)." + newFileName
    }
}

extension NSRegularExpression {
    convenience init(_ pattern: String) {
        do {
            try self.init(pattern: pattern)
        } catch {
            preconditionFailure("Illegal regular expression: \(pattern).")
        }
    }
}
