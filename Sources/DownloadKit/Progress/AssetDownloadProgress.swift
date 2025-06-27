//
//  AssetDownloadProgress.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 10/9/17.
//  Copyright © 2017 Blub Blub. All rights reserved.
//

import Foundation
import os.log

public class AssetDownloadProgress {
    public typealias Progress = Foundation.Progress
    
    public var log: Logger = logDK
    
    /// Nodes store a tree of progresses based on loaded identifiers.
    private var nodes = [String: ProgressNode]()
    
    private let syncQueue = DispatchQueue(label: "org.blubblub.progress.download.sync",
                                          qos: .background,
                                          attributes: [],
                                          autoreleaseFrequency: .inherit,
                                          target: nil)
    
    /// Transferring progresses that are mapped to nodes under the hood.
    public private(set) var progresses = [String: Progress]()
    
    /// Completed count.
    public private(set) var completedDownloadCount = 0
    
    /// Failed count.
    public private(set) var failedDownloadCount = 0
    
    private func node(for identifier: String, with items: [String: Progress]? = nil) -> ProgressNode? {
        var returnNode: ProgressNode?
        syncQueue.sync {
            guard progresses.count > 0 else { return }
            
            if let node = nodes[identifier] {
                returnNode = node
                return
            }
            
            guard let items = items, items.count > 0 else {
                log.debug("Requested progress node for items \(identifier), but there are no items specified and progress does not exist.")
                return
            }
            
            returnNode = ProgressNode(items: items)
            
            self.nodes[identifier] = returnNode
        }
        
        return returnNode
    }
    
    func add(items: [String: Progress]) {
        for (identifier, progress) in items {
            add(progress, for: identifier)
        }
    }
    
    private func add(_ progress: Progress, for identifier: String) {
        syncQueue.sync {
            
            progresses[identifier] = progress
            
            for (_, node) in nodes {
                node.retry(identifier, with: progress)
            }
        }
    }
    
    func complete(identifier: String, with error: Error?) {
        syncQueue.sync {
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
}

extension AssetDownloadProgress {
    
    public func progressNode(for identifier: String, downloadIdentifiers: [String]) -> ProgressNode? {
        var count = 0
        syncQueue.sync {
            count = progresses.count
        }
        
        guard count > 0 else {
            return nil
        }
        
        var items = [String: Progress]()
        syncQueue.sync {
            items = downloadIdentifiers.reduce(into: [String: Progress]()) {
                $0[$1] = progresses[$1]
            }
            
            if progresses.count > 0 && items.count == 0 {
                log.debug("There are progresses: \(self.progresses.count), but apparently not for this group assets: \(downloadIdentifiers.count)")
            }
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
            syncQueue.sync {
                let merged = newNode.merge(with: node)
                self.nodes[identifier] = merged
            }
            
            return self.nodes[identifier]
        }
    }
    
    
    func add(downloadItems: [Downloadable]) {
        let items = downloadItems.reduce(into: [String: Progress]()) {
            $0[$1.identifier] = $1.progress
        }

        add(items: items)
    }
}

