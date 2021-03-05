//
//  File.swift
//  
//
//  Created by Dal Rupnik on 2/11/21.
//

import Foundation
import os.log
import RealmSwift

public class RealmLocalCacheManager<L: Object> where L: LocalAssetFile {
    public var file = FileManager.default
    public var log: OSLog = logDK
    
    /// Target Realm to update
    public var configuration: Realm.Configuration = Realm.Configuration.defaultConfiguration
    
    public var assetSubdirectory = "assets/"
    public var excludeFilesFromBackup = true
    
    public var shouldDownload: ((AssetFile, RequestOptions) -> Bool)?

    private var realm: Realm {
        let realm = try! Realm(configuration: configuration)
        realm.autorefresh = false
        realm.refresh()
        
        return realm
    }
    
    public func store(asset: AssetFile, mirror: AssetFileMirror, at url: URL, options: RequestOptions) throws -> L {
        let targetUrl = L.targetUrl(for: asset, mirror: mirror, at: url, storagePriority: options.storagePriority, file: file)
        
        let directoryUrl = targetUrl.deletingLastPathComponent()
        
        let filename = targetUrl.lastPathComponent
        
        // Create directory and intermediate directories if it does not exist.
        if !file.fileExists(atPath: directoryUrl.path) {
            try file.createDirectory(atPath: directoryUrl.path, withIntermediateDirectories: true)
        }
        
        guard var finalFileUrl = file.generateLocalUrl(in: directoryUrl, for: filename) else {
            // Emit unable to generate valid local url, because of too many duplicates.
            throw NSError(domain: "org.blubblub.downloadkit", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Unable to generate local path, file already exists."])
        }
        
        // Update local path from finalFileUrl back to task, so it can be correctly saved.
        try file.moveItem(at: url, to: finalFileUrl)
        
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = excludeFilesFromBackup
        
        try finalFileUrl.setResourceValues(resourceValues)
        
        log.info("Downloaded file to: %@", finalFileUrl.absoluteString)
        
        // Store file into Realm
        let localAsset = createLocalAsset(for: asset, url: finalFileUrl)
        
        let realm = self.realm
        
        try realm.write {
            realm.add(localAsset)
        }
        
        return localAsset
    }
    
    
    /// Update/move files from cache to permanent storage or vice versa.
    /// - Parameters:
    ///   - assets: assets to operate on
    ///   - priority: priority to move to.
    public func updateStorage(assets: [AssetFile], to priority: StoragePriority) {
        // TODO: Implement this, moving from cache folder to app support folder and vice versa.
    }
    
    public func requestDownloads(assets: [AssetFile], options: RequestOptions) -> [AssetFile] {
        // Filter out binary and existing assets in local asset.
        
        let realm = self.realm
        
        // Get assets that need to be downloaded.
        let downloadableAssets = assets.filter { item in
            
            let identifier = item.id

            let localAsset = realm.object(ofType: L.self, forPrimaryKey: identifier)

            // No local asset, let's download.
            guard let asset = localAsset else {
                return true
            }
            
            // There is no local file URL, we should download it.
            if item.fileURL == nil {
                return true
            }
                        
            // Check if file supports modification date, only download if newer.
            if let localModifyDate = asset.modifyDate, let fileModifyDate = item.modifyDate {
                return fileModifyDate > localModifyDate
            }

            return shouldDownload?(item, options) ?? true
        }
        
        return downloadableAssets
    }
    
    /// Removes all traces of files in cache.
    public func reset() {
        let supportFiles = try? file.contentsOfDirectory(at: file.supportDirectoryURL.appendingPathComponent(assetSubdirectory),
                                                         includingPropertiesForKeys: nil,
                                                         options: []).map { $0.resolvingSymlinksInPath() }
        let cachedFiles = try? file.contentsOfDirectory(at: file.cacheDirectoryURL.appendingPathComponent(assetSubdirectory),
                                                        includingPropertiesForKeys: nil,
                                                        options: []).map { $0.resolvingSymlinksInPath() }
        
        let filesToRemove: [URL] = (supportFiles ?? []) + (cachedFiles ?? [])
        
        for currentFile in filesToRemove {
            do {
                try file.removeItem(at: currentFile)
                log.debug("[RealmLocalCacheManager]: Removed file: %@", currentFile.absoluteString)
            }
            catch let error {
                log.error("[RealmLocalCacheManager]: Error removing file: %@", error.localizedDescription)
            }
        }
        
        log.debug("[RealmLocalCacheManager]: Removed %lu files.", filesToRemove.count)
        
        let realm = self.realm
        let objects = realm.objects(L.self)
         
        try! realm.write {
            realm.delete(objects)
        }
        
        log.debug("[RealmLocalCacheManager]: Removed %lu objects.", objects.count)
    }
    
    public func cleanup(excluding urls: [URL]) {
        // Get all files from asset directly
        let assetDirectory = file.assetDirectoryURL(for: nil, assetDirectory: assetSubdirectory)
        
        do {
            let files = try file.contentsOfDirectory(at: assetDirectory, includingPropertiesForKeys: nil, options: []).map { $0.resolvingSymlinksInPath() }
            
            let filesToRemove = files.filter({ !urls.contains($0) })
            
            // Scan files and remove files that are not in urls array
            for currentFile in filesToRemove {
                do {
                    try file.removeItem(at: currentFile)
                    log.debug("[RealmLocalCacheManager]: Removed file: %@", currentFile.absoluteString)
                }
                catch let error {
                    log.error("[RealmLocalCacheManager]: Error removing file: %@", error.localizedDescription)
                }
            }
            
            log.debug("[RealmLocalCacheManager]: Removed %lu files.", filesToRemove.count)
            
        }
        catch {
            log.error("[RealmLocalCacheManager]: Error while scanning asset directory: %@", assetDirectory.absoluteString)
        }
        
        cleanupRealm(excluding: urls)
    }
    
    private func cleanupRealm(excluding urls: [URL]) {
        let realm = self.realm
        let objects = realm.objects(L.self)
        
        var deleteCounter = 0
         
        try! realm.write {
            for object in objects {
                // If the object has no URL, there is no file, we can delete the record.
                guard let fileURL = object.fileURL else {
                    realm.delete(object)
                    
                    deleteCounter += 1
                    continue
                }
                
                // Objects has url and we are excluding it. Continue.
                guard !urls.contains(fileURL) else {
                    continue
                }
                
                realm.delete(object)
                deleteCounter += 1
            }
        }
        
        log.debug("[RealmLocalCacheManager]: Removed %lu objects.", deleteCounter)
    }
    
    /// Creates a LocalAsset record with file path at URL.
    /// - Parameters:
    ///   - asset: asset to create record for
    ///   - url: url where file is located
    /// - Returns: local asset
    private func createLocalAsset(for asset: AssetFile, url: URL) -> L {

        // Create local asset
        var localAsset = L()
        localAsset.id = asset.id
        localAsset.fileURL = url
        
        if let modified = asset.modifyDate {
            localAsset.modifyDate = modified
        }
        else {
            localAsset.modifyDate = Date()
        }
        
        return localAsset
    }
}

private extension FileManager {
    var supportDirectoryURL: URL {
        return self.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
    
    var cacheDirectoryURL: URL {
        return self.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    func assetDirectoryURL(for directoryURL: URL? = nil, assetDirectory: String) -> URL {
        var directoryURL: URL! = directoryURL
        
        if directoryURL == nil {
            directoryURL = supportDirectoryURL
        }
        
        return directoryURL.appendingPathComponent(assetDirectory)
    }
}
