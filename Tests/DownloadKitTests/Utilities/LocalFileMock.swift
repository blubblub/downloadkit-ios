import Foundation
import RealmSwift
import DownloadKit

class LocalFile: Object, LocalResourceFile {
    @objc dynamic var identifier: String?
    
    @objc dynamic var modifyDate: Date?
    
    @objc dynamic var url: String?
    
    @objc dynamic var storagePriority: String = StoragePriority.cached.rawValue
    
    public override static func primaryKey() -> String? {
        return "identifier"
    }
    
    static func targetUrl(for asset: ResourceFile, mirror: ResourceFileMirror, at url: URL, storagePriority: StoragePriority, file: FileManager) -> URL {
        // Select directory based on state. Use is cached, everything else is stored in support.
        let targetUrl = storagePriority == .permanent ? file.supportDirectoryURL : file.cacheDirectoryURL
        let path = LocalFile.randomLocalPath(for: asset.id, fileExtension: (mirror.location as NSString).pathExtension)
        return targetUrl.appendingPathComponent(path)
    }
    
    var storage: StoragePriority {
        get { return StoragePriority(rawValue: storagePriority)! }
        set { storagePriority = newValue.rawValue }
    }
    
    var id: String {
        get { return identifier ?? "" }
        set { identifier = newValue }
    }
    
    var fileURL: URL? {
        get { return url.flatMap { URL(string: $0) } }
        set { url = newValue?.absoluteString }
    }
    
    class func randomLocalPath(for identifier: String, fileExtension: String) -> String {
        return "assets/" + identifier + "." + UUID().uuidString + "." + fileExtension
    }
}
