//
//  ResourceDownloadProgress.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 10/9/17.
//  Copyright © 2017 Blub Blub. All rights reserved.
//

import Foundation
import os.log

public actor ResourceDownloadProgress {
    
    public init() {}
    public typealias Progress = Foundation.Progress
    
    public let log: Logger = Logger.logResourceDownloadProgress
    
    /// Nodes store a tree of progresses based on loaded identifiers.
    private var nodes = [String: ProgressNode]()

    /// Transferring progresses that are mapped to nodes under the hood.
    public private(set) var progresses = [String: Progress]()
    private var downloadTaskIdentifiers = Set<String>()
    
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
        
        let returnNode = ProgressNode(tasks: Array(downloadTaskIdentifiers), items: items)
        
        self.nodes[identifier] = returnNode
        
        return returnNode
    }
    
    public func add(_ progress: Progress?, for identifier: String) {
        // Adds a progress for the specific identifier, if exists
        if let progress {
            progresses[identifier] = progress
        }
        
        downloadTaskIdentifiers.insert(identifier)
        
        for (_, node) in nodes {
            node.retry(identifier, with: progress)
        }
    }
    
    public func complete(identifier: String, with error: Error?) {
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
        
        downloadTaskIdentifiers.remove(identifier)
        
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
        
        let existingDownloadables = downloadIdentifiers.reduce(into: [String: Progress]()) {
            $0[$1] = progresses[$1]
        }
        
        // Get tasks that are in flight
        let tasks = Set(downloadIdentifiers).intersection(downloadTaskIdentifiers)
        
        if progresses.count > 0 && existingDownloadables.count == 0 {
            log.debug("There are progresses: \(self.progresses.count), but apparently not for this group resources: \(downloadIdentifiers.count)")
        }
        
        guard let newNode = ProgressNode(tasks: Array(tasks), items: existingDownloadables) else {
            return node(for: identifier, with: existingDownloadables)
        }
        
        // if there's already a node present and has same item count, return it.
        let node = self.node(for: identifier, with: existingDownloadables)
        if node?.hasSameItems(as: newNode) ?? false {
            return node
        } else {
            // otherwise merge newNode with old node, save and return it
            let merged = newNode.merge(with: node)
            self.nodes[identifier] = merged
            
            return self.nodes[identifier]
        }
    }
    
    public func add(download: DownloadTask, downloadable: Downloadable?) async {
        let progress = await downloadable?.progress
        
        add(progress, for: download.id)
    }
}

