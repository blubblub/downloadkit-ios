import Foundation
import DownloadKit

struct FileMirror: AssetFileMirror {
    var id: String
    
    var location: String
    
    var info: AssetFileInfo
    
    static func random(weight: Int) -> FileMirror {
        FileMirror(id: UUID().uuidString,
                   location: "https://example.com/file",
                   info: [WeightedMirrorPolicy.weightKey: weight])
    }
}

struct Asset: AssetFile {
    var id: String
    
    var main: AssetFileMirror = FileMirror.random(weight: 0)
    
    var alternatives: [AssetFileMirror] = [FileMirror]()
    
    var fileURL: URL?
}

extension Asset {
    static func sample(mirrorCount: Int) -> AssetFile {
        return Asset(id: "sample-id",
                     main: FileMirror.random(weight: 0),
                     alternatives: (1...mirrorCount).map { FileMirror.random(weight: $0) },
                     fileURL: nil)
    }
}
