//
//  WeightedMirrorPolicy.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 11/2/20.
//

import Foundation
import os.log

/// Weighted Mirror Policy will look for Integer under key `weight` in each mirror metadata.
/// It will select the mirror with highest weight, selecting next mirror. If the download fails,
/// it will continue to the mirror with the next highest weight. If it arrives to the last mirror,
/// and download fails, it will retry `numberOfRetries` times.
public actor WeightedMirrorPolicy: MirrorPolicy {
    public static let weightKey = "weight"
    
    private let log = Logger.logWeightedMirrorPolicy
    
    public var delegate: MirrorPolicyDelegate?
    
    /// How many times the policy will retry the last mirror.
    public let numberOfRetries: Int
    
    public init(numberOfRetries: Int = 3) {
        self.numberOfRetries = numberOfRetries
    }
    
    /// Function sorts all mirrors on resource file. Override this method if additional filter
    /// for the file mirrors need to be added (for example a file is not supported by the system).
    /// - Parameter resource: resource to sort mirrors for
    /// - Returns: sorted mirrors
    private func sortMirrors(for resource: ResourceFile) -> [ResourceFileMirror] {
        return resource.sortedMirrors()
    }
    
    public func mirror(for resource: ResourceFile, lastMirrorSelection: ResourceMirrorSelection?, error: Error?) -> ResourceMirrorSelection? {
        
        // if download was cancelled, no need to retry or return new mirror
        if (error as NSError?)?.code == NSURLErrorCancelled {
            return nil
        }
        
        let mirrors = sortMirrors(for: resource)
        
        var selectedIndex = 0
        
        // Downloadable from Mirror must exist here to be downloaded.
        var downloadable: Downloadable?
        
        // If we have tried a mirror and gotten an error, select a lower weight mirror.
        if let mirrorSelection = lastMirrorSelection, error != nil {
            log.info("Mirror errored: \(mirrorSelection.mirror.location), searching for next available on resource: \(resource.id)")
            
            // Find index of last mirror
            if let index = mirrors.firstIndex(where: { $0.id == mirrorSelection.mirror.id }) {
                selectedIndex = index + 1
            }
            
            // Ensure downloadable exists, otherwise continue
            var counter = selectedIndex
            
            while downloadable == nil, counter < mirrors.count  {
                downloadable = mirrors[counter].downloadable
                
                if downloadable != nil {
                    log.info("Selected next mirror: \(mirrors[counter].location) for resource: \(resource.id)")
                    
                    selectedIndex = counter
                    break
                }
                else {
                    counter += 1
                }
            }
        }
        
        // If we're out of mirrors, select last mirror and keep on trying from last mirror.
        if selectedIndex >= mirrors.count {
            selectedIndex = mirrors.count - 1
        }
        
        if downloadable == nil {
            downloadable = mirrors[selectedIndex].downloadable
        }
        
        // Only ask if we should retry in case there was an error.
        if error != nil && !shouldRetry(mirror: mirrors[selectedIndex], for: resource) {
            log.debug("Exhaused mirrors for resource: \(resource.id) Last: \(mirrors[selectedIndex].location)")
            
            delegate?.mirrorPolicy(self, didExhaustMirrorsIn: resource)
            return nil
        }
        
        guard let finalDownloadable = downloadable else {
            log.error("No Downloadable Mirrors found for resource: \(resource.id)")
            delegate?.mirrorPolicy(self, didFailToGenerateDownloadableIn: resource, for: mirrors[selectedIndex])
            return nil
        }
                
        //log.debug("Downloading resource: \(resource.id) from: \(mirrors[selectedIndex].location)")

        return ResourceMirrorSelection(id: resource.id, mirror: mirrors[selectedIndex], downloadable: finalDownloadable)
    }
    
    public func downloadComplete(for resource: ResourceFile) {
        // Download was completed for file, clean up the local cache for retries.
        
        for mirror in resource.sortedMirrors() {
            let mirrorKey = "\(resource.id)-\(mirror.id)"
            retryCounters[mirrorKey] = nil
        }
    }
    
    /// Holds a small retry access
    private var retryCounters = [String: Int]()
    
    private func shouldRetry(mirror: ResourceFileMirror, for resource: ResourceFile) -> Bool {
        let mirrorKey = "\(resource.id)-\(mirror.id)"
        
        var retryCounter = retryCounters[mirrorKey] ?? 0
        
        guard retryCounter < numberOfRetries else {
            return false
        }
        
        retryCounter += 1
        
        retryCounters[mirrorKey] = retryCounter
        
        return true
    }
}

extension WeightedMirrorPolicy {
    /// For testing purposes.
    /// - Parameter resource: resource file
    /// - Returns: Array of retry counters for each mirror the resource has.
    public func retryCounters(for resource: ResourceFile) -> [Int] {
        let keys = resource.sortedMirrors().map { "\(resource.id)-\($0.id)" }
        return keys.compactMap { retryCounters[$0] }
    }
}

private extension ResourceFile {
    func sortedMirrors() -> [ResourceFileMirror] {
        var mirrors = self.alternatives.sorted(by: { $0.weight > $1.weight })
        
        // Add main mirror on the end.
        mirrors.append(main)
        
        return mirrors
    }
}

public extension ResourceFileMirror {
    var weight: Int {
        return (info[WeightedMirrorPolicy.weightKey] as? Int) ?? 0
    }
}
