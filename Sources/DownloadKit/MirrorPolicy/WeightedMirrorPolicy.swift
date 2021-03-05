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
open class WeightedMirrorPolicy: MirrorPolicy {
    static let weightKey = "weight"
    
    public var log: OSLog = logDK
    
    public var delegate: MirrorPolicyDelegate?
    
    /// How many times the policy will retry the last mirror.
    public var numberOfRetries = 3
    
    public init() {
        
    }
    
    /// Function sorts all mirrors on asset file. Override this method if additional filter
    /// for the file mirrors need to be added (for example a file is not supported by the system).
    /// - Parameter asset: asset to sort mirrors for
    /// - Returns: sorted mirrors
    open func sortMirrors(for asset: AssetFile) -> [AssetFileMirror] {
        return asset.sortedMirrors()
    }
    
    public func mirror(for asset: AssetFile, lastMirrorSelection: AssetMirrorSelection?, error: Error?) -> AssetMirrorSelection? {
        let mirrors = sortMirrors(for: asset)
        
        var selectedIndex = 0
        
        // Downloadable from Mirror must exist here to be downloaded.
        var downloadable: Downloadable?
        
        // If we have tried a mirror and gotten an error, select a lower weight mirror.
        if let mirrorSelection = lastMirrorSelection, error != nil {
            // Find index of last mirror
  
            if let index = mirrors.firstIndex(where: { $0.id == mirrorSelection.id }) {
                selectedIndex = index + 1
            }
            
            // Ensure downloadable exists, otherwise continue
            var counter = selectedIndex
            
            while downloadable == nil, counter < mirrors.count  {
                downloadable = mirrors[counter].downloadable
                
                if downloadable != nil {
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
        
        // If we should retry.
        guard shouldRetry(mirror: mirrors[selectedIndex], for: asset) else {
            delegate?.mirrorPolicy(self, didExhaustMirrorsIn: asset)
            return nil
        }
        
        guard let finalDownloadable = downloadable else {
            log.error("[WeightedMirrorPolicy]: No Downloadable Mirrors found for asset: %@", asset.id)
            delegate?.mirrorPolicy(self, didFailToGenerateDownloadableIn: asset, for: mirrors[selectedIndex])
            return nil
        }

        return AssetMirrorSelection(id: asset.id, mirror: mirrors[selectedIndex], downloadable: finalDownloadable)
    }
    
    public func downloadComplete(for asset: AssetFile) {
        // Download was completed for file, clean up the local cache for retries.
        
        for mirror in asset.sortedMirrors() {
            let mirrorKey = "\(asset.id)-\(mirror.id)"
            retryCounters[mirrorKey] = nil
        }
    }
    
    /// Holds a small retry access
    private var retryCounters: [String: Int] = [:]
    
    private func shouldRetry(mirror: AssetFileMirror, for asset: AssetFile) -> Bool {
        let mirrorKey = "\(asset.id)-\(mirror.id)"
        
        var retryCounter = retryCounters[mirrorKey] ?? 0
        
        guard retryCounter < numberOfRetries else {
            return false
        }
        
        retryCounter += 1
        
        retryCounters[mirrorKey] = retryCounter
        
        return true
    }
}

private extension AssetFile {
    func sortedMirrors() -> [AssetFileMirror] {
        var mirrors = self.alternatives.sorted(by: { $0.weight > $1.weight })
        
        // Add main mirror on the end.
        mirrors.append(main)
        
        return mirrors
    }
}

private extension AssetFileMirror {
    var weight: Int {
        return (info[WeightedMirrorPolicy.weightKey] as? Int) ?? 0
    }
}
