//
//  RealmLocalCacheManager.swift
//  
//
//  Created by Dal Rupnik on 2/11/21.
//

import Foundation
import os.log
import RealmSwift

public final class RealmLocalCacheManager<L: Object>: @unchecked Sendable where L: LocalResourceFile {
    public let file = FileManager.default
    public let log = Logger(subsystem: "org.blubblub.downloadkit.realm.cache.local", category: "Cache")
    
    /// Target Realm to update
    public let configuration: Realm.Configuration
    
    public var resourceSubdirectory = "resources/"
    public var excludeFilesFromBackup = true
    
    public var shouldDownload: ((ResourceFile, RequestOptions) -> Bool)?

    private var realm: Realm {
        get throws {
            let realm = try Realm(configuration: configuration)
            realm.autorefresh = false
            realm.refresh()
            
            return realm
        }
    }
    
    // MARK: - Public
    
    public init(configuration: Realm.Configuration) {
        self.configuration = configuration
    }
    
    /// Creates a new local resource and stores it in realm database.
    /// - Parameters:
    ///   - resource: resource to store in realm.
    ///   - mirror: from which mirror the resource was downloaded.
    ///   - url: where the resource is stored.
    ///   - options: request options.
    /// - Throws: in case the file already exists at the target url.
    /// - Returns: local resource.
    public func store(resource: ResourceFile, mirror: ResourceFileMirror, at url: URL, options: RequestOptions) throws -> L {
        let targetUrl = L.targetUrl(for: resource, mirror: mirror, at: url, storagePriority: options.storagePriority, file: file)
        
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
        
        // Store file into Realm
        let localAsset = self.createLocalAsset(for: resource, url: finalFileUrl)
        let realm = try self.realm
        
        try realm.write {
            realm.add(localAsset, update: .modified)
        }
        
        log.info("Stored: \(resource.id) at: \(finalFileUrl.absoluteString)")
        
        return localAsset
    }
    
    
    /// Update/move files from cache to permanent storage or vice versa.
    /// - Parameters:
    ///   - assets: assets to operate on
    ///   - priority: priority to move to.
    public func updateStorage(assets: [ResourceFile], to priority: StoragePriority, onAssetChange: ((L) -> Void)?) {
        autoreleasepool {
            do {
                let realm = try self.realm
                
                for asset in assets {
                    if var localAsset = realm.object(ofType: L.self, forPrimaryKey: asset.id),
                       let localURL = localAsset.fileURL {
                        guard file.fileExists(atPath: localURL.path) else {
                            realm.delete(localAsset)
                            continue
                        }
                        // if priorities are the same, skip moving files
                        if localAsset.storage == priority { continue }
                        
                        let targetURL = L.targetUrl(for: asset, mirror: asset.main, // main mirror here?
                                                    at: localURL,
                                                    storagePriority: priority, file: file)
                        let directoryURL = targetURL.deletingLastPathComponent()
                                                
                        do {
                            if !file.fileExists(atPath: directoryURL.path) {
                                try file.createDirectory(atPath: directoryURL.path, withIntermediateDirectories: true)
                            }
                            
                            // move to new location
                            try file.moveItem(at: localURL, to: targetURL)
                            // update fileURL with new location and storage
                            realm.beginWrite()
                            localAsset.fileURL = targetURL
                            localAsset.storage = priority
                            realm.add(localAsset, update: .modified)
                            onAssetChange?(localAsset)
                            try realm.commitWrite()
                            log.info("Moved \(localURL.absoluteString) from to \(targetURL.absoluteString)")
                        } catch {
                            log.error("Error \(error.localizedDescription) moving file from: \(localURL.absoluteString) to \(targetURL.absoluteString)")
                        }
                    }
                }

            }
            catch {
                log.error("Error updating Realm store for files.")
            }
        }
    }
    
    /// Filters through `assets` and returns only those that are not downloaded.
    /// - Parameters:
    ///   - assets: assets we filter through.
    ///   - options: options
    /// - Returns: assets that are not yet stored locally.
    public func downloads(from assets: [ResourceFile], options: RequestOptions) -> [ResourceFile] {
        return autoreleasepool { () -> [ResourceFile] in
            guard let realm = try? self.realm else {
                return []
            }
                        
            // Get assets that need to be downloaded.
            let downloadableAssets = assets.filter { item in
                
                if let shouldDownload = shouldDownload {
                    return shouldDownload(item, options)
                }
                
                // No local asset, let's download.
                guard let asset = realm.object(ofType: L.self, forPrimaryKey: item.id), asset.fileURL != nil else {
                    return true
                }
                            
                // Check if file supports modification date, only download if newer.
                if let localModifyDate = asset.modifyDate, let fileModifyDate = item.modifyDate {
                    return fileModifyDate > localModifyDate
                }
                
                return false
            }
         
            return downloadableAssets
        }
    }
    
    /// Removes all traces of files in document and cache folder.
    /// Removes all objects from realm.
    public func reset() throws {
        let supportFiles = file.cachedFiles(directory: file.supportDirectoryURL,
                                            subdirectory: resourceSubdirectory)
        
        let cachedFiles = file.cachedFiles(directory: file.cacheDirectoryURL,
                                           subdirectory: resourceSubdirectory)
        
        let filesToRemove = supportFiles + cachedFiles
        removeFiles(filesToRemove)
        
        let realm = try self.realm
        
        let objects = realm.objects(L.self)
        
        try realm.write {
            realm.delete(objects)
        }
        
        log.debug("Removed \(filesToRemove.count) files.")
        log.debug("Removed \(objects.count) objects.")
    }
    
    public func cleanup(excluding urls: Set<URL>) throws {
        let files = file.cachedFiles(directory: file.supportDirectoryURL,
                                     subdirectory: resourceSubdirectory)
        
        let filesToRemove = files.filter({ !urls.contains($0) })
        removeFiles(filesToRemove)
        
        log.debug("Removed \(filesToRemove.count) files.")
        
        try cleanupRealm(excluding: Set(urls))
    }
    
    // MARK: - Private
    
    
    /// Helper function that removes items from file system.
    /// - Parameter items: items to remove from file system.
    private func removeFiles(_ items: [URL]) {
        for item in items {
            do {
                try file.removeItem(at: item)
                log.debug("Removed file: \(item.absoluteString)")
            } catch {
                log.error("Error removing file: \(error.localizedDescription)")
            }
        }
    }
    
    private func cleanupRealm(excluding urls: Set<URL>) throws {
        let realm = try self.realm
        let objects = realm.objects(L.self)
        
        var deleteCounter = 0
         
        try? realm.write {
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
        
        log.debug("Removed \(deleteCounter) objects.")
    }
    
    private func removeAssetsWithoutLocalFile(assets: [ResourceFile]) throws {
        let realm = try self.realm
        
        let localAssets = assets.compactMap { realm.object(ofType: L.self, forPrimaryKey: $0.id) }
        do {
            try realm.write {
                for asset in localAssets where !assetExistsLocally(asset: asset) {
                    realm.delete(asset)
                }
            }
        } catch {
            log.error("Error while removing assets \(error.localizedDescription)")
        }
    }
    
    private func assetExistsLocally(asset: L) -> Bool {
        // if we don't have file URL, delete
        guard let url = asset.fileURL else {
            return false
        }
        
        return file.fileExists(atPath: url.path)
    }
    
    /// Creates a LocalAsset record with file path at URL.
    /// - Parameters:
    ///   - asset: asset to create record for
    ///   - url: url where file is located
    /// - Returns: local asset
    private func createLocalAsset(for asset: ResourceFile, url: URL) -> L {
        var localAsset = L()
        localAsset.id = asset.id
        localAsset.fileURL = url
        localAsset.modifyDate = asset.modifyDate ?? Date()
        
        return localAsset
    }
}

public extension FileManager {
    func cachedFiles(directory: URL, subdirectory: String) -> [URL] {
        do {
            let directory = directory.appendingPathComponent(subdirectory)
            let files = try contentsOfDirectory(at: directory,
                                                includingPropertiesForKeys: nil,
                                                options: []).map { $0.resolvingSymlinksInPath() }
            
            return files
        } catch {
            return []
        }
    }
    
    var supportDirectoryURL: URL {
        return self.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
    
    var cacheDirectoryURL: URL {
        return self.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }
}
