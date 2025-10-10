//
//  MirrorPolicy.swift
//  BlubBlubCore
//
//  Created by Dal Rupnik on 10/30/20.
//

import Foundation

/// Mirror policy is responsible for picking a mirror to download when required.
/// - Certain Mirror Policies can have specific retry logic.
public protocol MirrorPolicy : Actor {
    
    /// This method will be called on Mirror policy when a transfer from a mirror fails.
    /// Method should return a retry configuration, if file should be retried.
    /// - Parameters:
    ///   - mirror: mirror that the transfer failed.
    ///   - error: error that might have appeared.
    func downloadable(for resource: ResourceFile, lastDownloadableIdentifier: String?, error: Error?) -> Downloadable?
}

public protocol MirrorPolicyDelegate: AnyObject, Sendable {
    
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
