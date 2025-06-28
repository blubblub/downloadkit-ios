import Foundation
import DownloadKit

struct FileMirror: ResourceFileMirror, @unchecked Sendable {
    var id: String
    
    var location: String
    
    var info: ResourceFileInfo
    
    static func random(weight: Int) -> FileMirror {
        FileMirror(id: UUID().uuidString,
                   location: "https://example.com/file",
                   info: [WeightedMirrorPolicy.weightKey: weight])
    }
}

struct Resource: ResourceFile {
    var id: String
    
    var main: ResourceFileMirror = FileMirror.random(weight: 0)
    
    var alternatives: [ResourceFileMirror] = [FileMirror]()
    
    var fileURL: URL?
}

extension Resource {
    static func sample(mirrorCount: Int) -> ResourceFile {
        return Resource(id: "sample-id",
                        main: FileMirror.random(weight: 0),
                        alternatives: (1...mirrorCount).map { FileMirror.random(weight: $0) },
                        fileURL: nil)
    }
}
