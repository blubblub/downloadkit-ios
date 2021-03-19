//
//  MirrorPolicy.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 10/30/20.
//

import Foundation

public struct AssetMirrorSelection {
    
    public let id: String
    
    /// Mirror to retry
    public let mirror: AssetFileMirror
    
    /// Downloadable
    public let downloadable: Downloadable
    
    /// Option to retry
    public var option = QueueOption.normal
}

extension AssetMirrorSelection {
    
    public enum QueueOption {
        /// The Mirror should enqueue normally.
        case normal
        
        /// The Mirror should enqueue on top of the normal queue.
        case priority
        
        /// The Mirror should get a highest priority and will be put on Priority Queue.
        /// If PriorityQueue is not available, then this is the same as `priority`.
        case highPriority
    }
    
}

/// Mirror policy is responsible for picking a mirror to download when required.
/// - Certain Mirror Policies can have specific retry logic.
public protocol MirrorPolicy {
    
    var delegate: MirrorPolicyDelegate? { get set }
    
    /// This method will be called on Mirror policy when a transfer from a mirror fails.
    /// Method should return a retry configuration, if file should be retried.
    /// - Parameters:
    ///   - asset: asset to download.
    ///   - mirror: mirror that the transfer failed.
    ///   - error: error that might have appeared.
    func mirror(for asset: AssetFile, lastMirrorSelection: AssetMirrorSelection?, error: Error?) -> AssetMirrorSelection?
    
    /// Call this method on MirrorPolicy to let it know the file is ready.
    /// - Parameter asset: asset
    func downloadComplete(for asset: AssetFile)
}

public protocol MirrorPolicyDelegate: class {
    
    /// Will be called after all retry attempts to available mirrors are completed.
    /// - Parameters:
    ///   - mirrorPolicy: mirror policy
    ///   - file: asset file
    func mirrorPolicy(_ mirrorPolicy: MirrorPolicy, didExhaustMirrorsIn file: AssetFile)
    
    /// Will be called if it is impossible to generate a downloadable from selected mirror.
    /// Policy should continue according to settings.
    /// - Parameters:
    ///   - mirrorPolicy: mirror
    ///   - file: file
    ///   - mirror: mirror
    func mirrorPolicy(_ mirrorPolicy: MirrorPolicy, didFailToGenerateDownloadableIn file: AssetFile, for mirror: AssetFileMirror)
}
