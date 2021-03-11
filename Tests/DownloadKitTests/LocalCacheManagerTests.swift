import XCTest
import RealmSwift
@testable import DownloadKit

class LocalCacheManagerTests: XCTestCase {
    
    /// In memory realm configuration.
    let config = Realm.Configuration(inMemoryIdentifier: "memory-id")
    let cachedOptions = RequestOptions(downloadPriority: .normal, storagePriority: .cached)
    let permanentOptions = RequestOptions(downloadPriority: .normal, storagePriority: .permanent)
    
    var manager: RealmLocalCacheManager<LocalFile>!
    
    var url: URL {
        return try! FileManager.createFileOnDisk()
    }
    
    override func setUpWithError() throws {
        manager = RealmLocalCacheManager<LocalFile>(configuration: config)
    }

    override func tearDownWithError() throws {
        manager.cleanup(excluding: [])
        manager = nil
    }
    
    func testStoringAssetFile() throws {
        let asset = Asset(id: UUID().uuidString)
        
        let stored = try manager.store(asset: asset, mirror: asset.main, at: url, options: cachedOptions)
        
        XCTAssertNotNil(stored, "Local asset was stored in realm.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.fileURL!.path))
    }
    
    func testRequestingDownloadsOnEmptyCacheReturnsAllAssets() {
        let assets: [Asset] = (0..<5).map({ _ in Asset(id: UUID().uuidString) })
        let requests = manager.requestDownloads(assets: assets, options: cachedOptions)
        
        XCTAssertEqual(5, requests.count, "Manager should return 5 assets that need to be downloaded.")
    }
    
    func testRequestingDownloadsReturnsCorrectAssets() throws {
        let assets: [Asset] = (0..<5).map({ _ in Asset(id: UUID().uuidString) })
        
        // store first asset
        let first = assets.first!
        let _ = try manager.store(asset: first, mirror: first.main, at: url, options: cachedOptions)
        
        // request downloads should only return 4 assets since the first one is saved
        let requests = manager.requestDownloads(assets: assets, options: cachedOptions)
        
        XCTAssertEqual(4, requests.count, "Manager should return only 4 assets that need to be downloaded.")
    }
    
    func testUpdatingStorage() throws {
        let assets: [Asset] = (0..<5).map({ _ in Asset(id: UUID().uuidString) })
        
        // store to realm
        for asset in assets {
            let _ = try manager.store(asset: asset, mirror: asset.main, at: url, options: cachedOptions)
        }
        
        // update stored assets and move them to permanent storage
        manager.updateStorage(assets: assets, to: .permanent)
        
        let requests = manager.requestDownloads(assets: assets, options: permanentOptions)
        XCTAssertEqual(requests.count, 0, "All assets should be stored locally in permanent storage")
    }
    
    func testResetingLocalCache() throws {
        let assets: [Asset] = (0..<5).map({ _ in Asset(id: UUID().uuidString) })
        
        // store to realm
        for asset in assets {
            let _ = try manager.store(asset: asset, mirror: asset.main, at: url, options: cachedOptions)
        }
        
        // reset local cache
        manager.reset()
        
        let requests = manager.requestDownloads(assets: assets, options: permanentOptions)
        XCTAssertEqual(requests.count, 5, "Manager should return 5 requests, since everything was removed.")
    }
    
    func testCleanup() throws {
        let assets: [Asset] = (0..<5).map({ _ in Asset(id: UUID().uuidString) })
        
        // store to realm
        let localAssets = assets.map { asset in
            return try! manager.store(asset: asset, mirror: asset.main, at: url, options: permanentOptions)
        }
        
        // clean up everything except the first asset
        manager.cleanup(excluding: Set([localAssets.first!.fileURL!]))
        
        
        let requested = manager.requestDownloads(assets: assets, options: permanentOptions)
        
        XCTAssertEqual(requested.count, 4)
    }
    
}

// MARK: - Mocks

class LocalFile: Object, LocalAssetFile {
    @objc dynamic var identifier: String?
    
    @objc dynamic var modifyDate: Date?
    
    @objc dynamic var url: String?
    
    @objc dynamic var storagePriority: String = StoragePriority.cached.rawValue
    
    public override static func primaryKey() -> String? {
        return "identifier"
    }
    
    static func targetUrl(for asset: AssetFile, mirror: AssetFileMirror, at url: URL, storagePriority: StoragePriority, file: FileManager) -> URL {
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

extension FileManager {
    var supportDirectoryURL: URL {
        return self.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
    
    var cacheDirectoryURL: URL {
        return self.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }
    
    static func createFileOnDisk() throws -> URL {
        let filename = FileManager.default.cacheDirectoryURL.appendingPathComponent(UUID().uuidString)

        // we're just outputting an emoji into a file
        try "😃".write(to: filename, atomically: true, encoding: String.Encoding.utf8)
        
        return filename
    }
}

