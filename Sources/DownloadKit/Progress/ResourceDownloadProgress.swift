//
//  AssetDownloadProgress.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 10/9/17.
//  Copyright © 2017 Blub Blub. All rights reserved.
//

import Foundation
import os.log

public actor ResourceDownloadProgress {
    public typealias Progress = Foundation.Progress
    
    public let log: Logger = logDK
    
    /// Nodes store a tree of progresses based on loaded identifiers.
    private var nodes = [String: ProgressNode]()

    /// Transferring progresses that are mapped to nodes under the hood.
    public private(set) var progresses = [String: Progress]()
    
    /// Completed count.
    public private(set) var completedDownloadCount = 0
    
    /// Failed count.
    public private(set) var failedDownloadCount = 0
    
    private func node(for identifier: String, with items: [String: Progress]? = nil) -> ProgressNode? {
        guard progresses.count > 0 else { return nil }
        
        if let node = nodes[identifier] {
            return node
        }
        
        guard let items = items, items.count > 0 else {
            log.debug("Requested progress node for items \(identifier), but there are no items specified and progress does not exist.")
            return nil
        }
        
        let returnNode = ProgressNode(items: items)
        
        self.nodes[identifier] = returnNode
        
        return returnNode
    }
    
    func add(items: [String: Progress]) {
        for (identifier, progress) in items {
            add(progress, for: identifier)
        }
    }
    
    private func add(_ progress: Progress, for identifier: String) {
        progresses[identifier] = progress
        
        for (_, node) in nodes {
            node.retry(identifier, with: progress)
        }
    }
    
    func complete(identifier: String, with error: Error?) {
        var completedNodes: [String] = []
        
        for (key, node) in nodes {
            
            node.complete(identifier, with: error)
            
            if node.isCompleted {
                completedNodes.append(key)
            }
        }
        
        // Clean up nodes after they complete transferring.
        for key in completedNodes {
            nodes[key] = nil
        }
        
        if error == nil {
            completedDownloadCount += progresses[identifier] != nil ? 1 : 0
        } else {
            failedDownloadCount += progresses[identifier] != nil ? 1 : 0
        }
        
        progresses[identifier] = nil
    }
}

extension ResourceDownloadProgress {
    
    public func progressNode(for identifier: String, downloadIdentifiers: [String]) -> ProgressNode? {
        let count = progresses.count

        guard count > 0 else {
            return nil
        }
        
        let items = downloadIdentifiers.reduce(into: [String: Progress]()) {
            $0[$1] = progresses[$1]
        }
        
        if progresses.count > 0 && items.count == 0 {
            log.debug("There are progresses: \(self.progresses.count), but apparently not for this group assets: \(downloadIdentifiers.count)")
        }
        
        guard let newNode = ProgressNode(items: items) else {
            return node(for: identifier, with: items)
        }
        
        // if there's already a node present and has same item count, return it.
        let node = self.node(for: identifier, with: items)
        if node?.hasSameItems(as: newNode) ?? false {
            return node
        } else {
            // otherwise merge newNode with old node, save and return it
            let merged = newNode.merge(with: node)
            self.nodes[identifier] = merged
            
            return self.nodes[identifier]
        }
    }
    
    
    func add(downloadItems: [Downloadable]) async {
        
        var items = [String: Progress]()
        
        for item in downloadItems {
            let identifier = await item.identifier
            items[identifier] = await item.progress
        }
        
        add(items: items)
    }
}

