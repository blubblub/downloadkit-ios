//
//  Resource.swift
//  DownloadKit
//
//  Created by Dal Rupnik on 30.06.2025.
//

import Foundation

/// Default implementation of ResourceFileMirror
public struct FileMirror: ResourceFileMirror, Sendable {
    public let id: String
    public let location: String
    public let info: ResourceFileInfo
    
    public init(id: String, location: String, info: ResourceFileInfo) {
        self.id = id
        self.location = location
        self.info = info
    }
}

/// Default implementation of ResourceFile
public struct Resource: ResourceFile, Sendable {
    public var id: String
    public var main: ResourceFileMirror
    public var alternatives: [ResourceFileMirror]
    public var createdAt: Date?
    
    public init(id: String, main: ResourceFileMirror, alternatives: [ResourceFileMirror] = [], fileURL: URL? = nil, createdAt: Date? = nil) {
        self.id = id
        self.main = main
        self.alternatives = alternatives
        self.createdAt = createdAt
    }
}
