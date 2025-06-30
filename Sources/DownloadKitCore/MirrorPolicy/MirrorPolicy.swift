//
//  MirrorPolicy.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 10/30/20.
//

import Foundation

public struct ResourceMirrorSelection : Sendable {
    
    public let id: String
    
    /// Mirror to retry
    public let mirror: ResourceFileMirror
    
    /// Downloadable
    public let downloadable: Downloadable
    
    /// Option to retry
    public var option = QueueOption.normal
    
    public init(id: String, mirror: ResourceFileMirror, downloadable: Downloadable, option: QueueOption = .normal) {
        self.id = id
        self.mirror = mirror
        self.downloadable = downloadable
        self.option = option
    }
}

extension ResourceMirrorSelection {
    
    public enum QueueOption : Sendable {
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
    ///   - resource: resource to download.
    ///   - mirror: mirror that the transfer failed.
    ///   - error: error that might have appeared.
    func mirror(for resource: ResourceFile, lastMirrorSelection: ResourceMirrorSelection?, error: Error?) -> ResourceMirrorSelection?
    
    /// Call this method on MirrorPolicy to let it know the file is ready.
    /// - Parameter resources: resources
    func downloadComplete(for resource: ResourceFile)
}

public protocol MirrorPolicyDelegate: AnyObject {
    
    /// Will be called after all retry attempts to available mirrors are completed.
    /// - Parameters:
    ///   - mirrorPolicy: mirror policy
    ///   - file: resource file
    func mirrorPolicy(_ mirrorPolicy: MirrorPolicy, didExhaustMirrorsIn file: ResourceFile)
    
    /// Will be called if it is impossible to generate a downloadable from selected mirror.
    /// Policy should continue according to settings.
    /// - Parameters:
    ///   - mirrorPolicy: mirror
    ///   - file: file
    ///   - mirror: mirror
    func mirrorPolicy(_ mirrorPolicy: MirrorPolicy, didFailToGenerateDownloadableIn file: ResourceFile, for mirror: ResourceFileMirror)
}
