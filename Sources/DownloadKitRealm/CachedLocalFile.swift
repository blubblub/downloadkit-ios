import Foundation
import RealmSwift
import DownloadKitCore

public final class CachedLocalFile: Object, LocalResourceFile, @unchecked Sendable {
    @objc public dynamic var identifier: String?
    
    @objc public dynamic var modifyDate: Date?
    
    @objc public dynamic var url: String?
    
    @objc public dynamic var storagePriority: String = StoragePriority.cached.rawValue
    
    public override static func primaryKey() -> String? {
        return "identifier"
    }
    
    public static func targetUrl(for resource: ResourceFile, mirror: ResourceFileMirror, at url: URL, storagePriority: StoragePriority, file: FileManager) -> URL {
        // Select directory based on state. Use is cached, everything else is stored in support.
        let targetUrl = storagePriority == .permanent ? file.supportDirectoryURL : file.cacheDirectoryURL
        let path = CachedLocalFile.randomLocalPath(for: resource.id, fileExtension: (mirror.location as NSString).pathExtension)
        return targetUrl.appendingPathComponent(path)
    }
    
    public var storage: StoragePriority {
        get { return StoragePriority(rawValue: storagePriority)! }
        set { storagePriority = newValue.rawValue }
    }
    
    public var id: String {
        get { return identifier ?? "" }
        set { identifier = newValue }
    }
    
    public var fileURL: URL? {
        get { return url.flatMap { URL(string: $0) } }
        set { url = newValue?.absoluteString }
    }
    
    public class func randomLocalPath(for identifier: String, fileExtension: String) -> String {
        return "resources/" + identifier + "." + UUID().uuidString + "." + fileExtension
    }
}
