import Foundation
import RealmSwift
import DownloadKitCore

public final class CachedLocalFile: Object, LocalResourceFile, @unchecked Sendable {
    
    
    @Persisted public var identifier: String?
    @Persisted public var mirrorIdentifier: String?
    @Persisted public var createdDate: Date?
    @Persisted public var url: String?
    @Persisted public var storagePriority: String = StoragePriority.cached.rawValue
    
    
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
    
    public var mirrorId: String {
        get { return mirrorIdentifier ?? "" }
        set { mirrorIdentifier = newValue }
    }
    
    public var fileURL: URL {
        get {
            guard let url = url else {
                fatalError("First set URL before accessing fileURL!")
            }
            
            return URL(string: url)!
        }
        set { url = newValue.absoluteString }
    }
    
    public var createdAt: Date {
        get { return createdDate ?? Date() }
        set { createdDate = newValue }
    }
    
    public class func randomLocalPath(for identifier: String, fileExtension: String) -> String {
        return "resources/" + identifier + "." + UUID().uuidString + "." + fileExtension
    }
}
