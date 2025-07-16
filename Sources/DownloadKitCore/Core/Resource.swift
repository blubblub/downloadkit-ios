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
    
    public static func random(weight: Int) -> FileMirror {
        FileMirror(id: UUID().uuidString,
                   location: "https://example.com/file",
                   info: [WeightedMirrorPolicy.weightKey: weight])
    }
}

/// Default implementation of ResourceFile
public struct Resource: ResourceFile, Sendable {
    public var id: String
    public var main: ResourceFileMirror
    public var alternatives: [ResourceFileMirror]
    public var modifyDate: Date?
    
    public init(id: String, main: ResourceFileMirror, alternatives: [ResourceFileMirror] = [], fileURL: URL? = nil, modifyDate: Date? = nil) {
        self.id = id
        self.main = main
        self.alternatives = alternatives
        self.modifyDate = modifyDate
    }
}

public extension Resource {
    static func sample(mirrorCount: Int) -> Resource {
        return Resource(id: "sample-id",
                        main: FileMirror.random(weight: 0),
                        alternatives: (1...mirrorCount).map { FileMirror.random(weight: $0) },
                        fileURL: nil)
    }
}
