//
//  RealmLocalCacheManager.swift
//  
//
//  Created by Dal Rupnik on 2/11/21.
//

import Foundation
import DownloadKitCore
import RealmSwift
import os.log

public final class RealmLocalCacheManager<L: Object>: ResourceFileRetrievable, Sendable where L: LocalResourceFile {
    public let log = Logger(subsystem: "org.blubblub.downloadkit.realm.cache.local", category: "Cache")
    
    /// Target Realm to update
    public let configuration: Realm.Configuration
    
    public let resourceSubdirectory : String
    public let excludeFilesFromBackup : Bool
    
    public let shouldDownload: (@Sendable (ResourceFile, RequestOptions) -> Bool)?
    
    private var file : FileManager {
        FileManager.default
    }

    private var realm: Realm {
        get throws {
            let realm = try Realm(configuration: configuration)
            realm.autorefresh = false
            realm.refresh()
            
            return realm
        }
    }
    
    // MARK: - Public
    
    public init(configuration: Realm.Configuration,
                resourceSubdirectory: String = "resources/",
                excludeFilesFromBackup: Bool = true,
                shouldDownload: (@Sendable (ResourceFile, RequestOptions) -> Bool)? = nil) {
        self.configuration = configuration
        self.resourceSubdirectory = resourceSubdirectory
        self.excludeFilesFromBackup = excludeFilesFromBackup
        self.shouldDownload = shouldDownload
    }
    
    
    /// Returns fileURL to resource id, if available.
    /// - Parameter resourceId: resource id to fetch URL for
    /// - Returns: URL if exists.
    public func fileURL(for resourceId: String) -> URL? {
        let realm = try? self.realm
        
        guard let localResource = realm?.object(ofType: L.self, forPrimaryKey: resourceId) else {
            return nil
        }
        
        if file.fileExists(atPath: localResource.fileURL.path) {
            return localResource.fileURL
        }
        
        
        // If it does not exist, we handle case of moving the sandbox then.
        // We should check both application support and caches directories, by replacing the first part of the path.
        
        
        let updatedURL = replaceSandboxURL(in: localResource.fileURL, for: localResource.storage)
        
        if file.fileExists(atPath: updatedURL.path) {
            return updatedURL
        }
        
        return nil
    }
    
    private func replaceSandboxURL(in url: URL, for storage: StoragePriority) -> URL {
        //
        
        
        let replacedURL: URL
        
        if storage == .cached {
            replacedURL = file.cacheDirectoryURL
        }
        else {
            replacedURL = file.supportDirectoryURL
        }
        //file:///var/mobile/Containers/Data/Application/74BD8E49-F863-4B7F-949C-0FAF674D075B/Library/Caches/resources/63eb5f332c3c9aba159a1834.A7804343-6ABE-4376-8754-0655C6FDF259.png
        // TODO: Implement here the replacement of first part of the URL. You can detect this by searching for "resources/" part of the directory, before it it should be replaced with the replaced URL.
        
        return replacedURL
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
            throw DownloadKitError.cache(.cannotGenerateLocalPath("file already exists at target location"))
        }
                
        // Update local path from finalFileUrl back to task, so it can be correctly saved.
        try file.moveItem(at: url, to: finalFileUrl)
        
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = excludeFilesFromBackup
        
        try finalFileUrl.setResourceValues(resourceValues)
        
        // Store file into Realm
        let localResource = self.createLocalResource(for: resource, mirror: mirror, url: finalFileUrl)
        let realm = try self.realm
        
        try realm.write {
            realm.add(localResource, update: .modified)
        }
        
        log.info("Stored: \(resource.id) at: \(finalFileUrl.absoluteString)")
        
        return localResource
    }
    
    
    /// Update/move files from cache to permanent storage or vice versa.
    /// - Parameters:
    ///   - resources: resources to operate on
    ///   - priority: priority to move to.
    public func updateStorage(resources: [ResourceFile], to priority: StoragePriority) -> [L] {
        var changedResources = [L]()
        
        do {
            let realm = try self.realm
            
            for resource in resources {
                if var localResource = realm.object(ofType: L.self, forPrimaryKey: resource.id) {
                    
                    let localURL = localResource.fileURL
                    guard file.fileExists(atPath: localURL.path) else {
                        try realm.write {
                            realm.delete(localResource)
                        }
                        continue
                    }
                    // if priorities are the same, skip moving files
                    if localResource.storage == priority { continue }
                    
                    let targetURL = L.targetUrl(for: resource, mirror: resource.main, // main mirror here?
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
                        localResource.fileURL = targetURL
                        localResource.storage = priority
                        realm.add(localResource, update: .modified)
                        
                        try realm.commitWrite()
                        
                        changedResources.append(localResource)
                        
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
        
        return changedResources
    }
    
    /// Filters through `resources` and returns only those that are not downloaded.
    /// Filters all resource files in array to find those missing from local file system.
    /// - Parameter resources: list of resources to filter
    /// - Returns: filtered list of resources
    func requestDownloads(resources: [ResourceFile], options: RequestOptions = RequestOptions()) async -> [DownloadRequest] {
        autoreleasepool {
            do {
                // Call the handler to update resources that might have been already downloaded.
                // This is needed, for example, when ResourceManager was paused.
                
                try removeResourcesWithoutLocalFile(resources: resources)
                
                // Get resources that need to be downloaded.
                let downloadableResources = downloads(from: resources, options: options)
                
                let downloadRequests: [DownloadRequest] = downloadableResources.compactMap { resource -> DownloadRequest? in
                    guard let downloadable = resource.main.downloadable else { return nil }
                    let mirrorSelection = ResourceMirrorSelection(id: resource.id, mirror: resource.main, downloadable: downloadable)
                    return DownloadRequest(resource: resource, options: options, mirror: mirrorSelection)
                }
                
                return downloadRequests
            }
            catch {
                log.error("Error while requesting downloads: \(error.localizedDescription)")
                return []
            }
        }
    }
    
    /// Filters through `resources` and returns only those that are not downloaded.
    /// - Parameters:
    ///   - resources: resources we filter through.
    ///   - options: options
    /// - Returns: resources that are not yet stored locally.
    public func downloads(from resources: [ResourceFile], options: RequestOptions) -> [ResourceFile] {
        guard let realm = try? self.realm else {
            return []
        }
                    
        // Get resources that need to be downloaded.
        let downloadableResources = resources.filter { item in
            
            if let shouldDownload = shouldDownload {
                return shouldDownload(item, options)
            }
            
            // No local resource, let's download.
            guard let resource = realm.object(ofType: L.self, forPrimaryKey: item.id) else {
                return true
            }
                        
            // Check if file supports modification date, only download if newer.
            if let localCreatedAt = resource.createdAt, let fileCreatedAt = item.createdAt {
                return fileCreatedAt > localCreatedAt
            }
            
            return false
        }
     
        return downloadableResources
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
    
    public func cleanup(excluding ids: Set<String>) throws {
        let files = file.cachedFiles(directory: file.supportDirectoryURL,
                                     subdirectory: resourceSubdirectory)
        
        var urlsToRemove: Set<URL> = Set(files)
        
        // Pull all cached files from database.
        let objectsInDatabase = try realm.objects(L.self)
        
        for object in objectsInDatabase {
            // If ids contain object, then remove the file from removal array
            if ids.contains(object.id) {
                urlsToRemove.remove(object.fileURL)
            }
        }
        
        // Filter objects
        
        removeFiles(Array(urlsToRemove))
        
        try cleanupRealm(excluding: ids)
                
        log.debug("Removed \(urlsToRemove.count) files.")
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
    
    private func cleanupRealm(excluding ids: Set<String>) throws {
        let realm = try self.realm
        let objects = realm.objects(L.self)
        
        var deleteCounter = 0
         
        try? realm.write {
            for object in objects {
                // If ids are matching.
                if ids.contains(object.id) {
                    continue
                }
                
                realm.delete(object)
                deleteCounter += 1
            }
        }
        
        log.debug("Removed \(deleteCounter) objects.")
    }
    
    private func removeResourcesWithoutLocalFile(resources: [ResourceFile]) throws {
        let realm = try self.realm
        
        let localResources = resources.compactMap { realm.object(ofType: L.self, forPrimaryKey: $0.id) }
        do {
            try realm.write {
                for resource in localResources where !resourceExistsLocally(resource: resource) {
                    realm.delete(resource)
                }
            }
        } catch {
            log.error("Error while removing resources \(error.localizedDescription)")
        }
    }
    
    private func resourceExistsLocally(resource: L) -> Bool {
        let url = resource.fileURL
        
        return file.fileExists(atPath: url.path)
    }
    
    /// Creates a LocalResource record with file path at URL.
    /// - Parameters:
    ///   - resource: resource to create record for
    ///   - url: url where file is located
    /// - Returns: local resource
    private func createLocalResource(for resource: ResourceFile, mirror: ResourceFileMirror, url: URL) -> L {
        var localResource = L()
        localResource.id = resource.id
        localResource.mirrorId = mirror.id
        localResource.fileURL = url
        localResource.createdAt = resource.createdAt ?? Date()
        
        return localResource
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
