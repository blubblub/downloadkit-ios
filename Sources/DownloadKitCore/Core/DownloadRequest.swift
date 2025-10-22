//
//  DownloadRequest.swift
//
//  Created by Dal Rupnik on 10/18/22.
//

import Foundation
import os.log

/// A download request, usually created by the cache. It's used to ask cache for a resource file,
/// and if not available, a DownloadRequest that can be processed is created.
public final class DownloadRequest: Sendable, Equatable {
    public let resource: ResourceFile
    public let options: RequestOptions
    
    private let log = Logger(subsystem: "org.blubblub.downloadkit.manager", category: "DownloadRequest")

    public init(resource: ResourceFile, options: RequestOptions) {
        self.resource = resource
        self.options = options
    }
    
    public static func == (lhs: DownloadRequest, rhs: DownloadRequest) -> Bool {
        return lhs.id == rhs.id
    }
        
    public var id: String {
        return resource.id
    }
}
