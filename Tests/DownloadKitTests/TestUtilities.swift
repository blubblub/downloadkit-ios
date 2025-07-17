//
//  TestUtilities.swift
//  DownloadKitTests
//
//  Created by Dal Rupnik on 30.06.2025.
//

import Foundation
import Realm
import RealmSwift
@testable import DownloadKit

/// Thread-safe counter using actor for concurrency
actor ActorCounter {
    private var count = 0
    
    func increment() {
        count += 1
    }
    
    func setValue(_ newValue: Int) {
        count = newValue
    }
    
    var value: Int {
        count
    }
}

/// Thread-safe array using actor for concurrency
actor ActorArray<T> {
    private var items: [T] = []
    
    func append(_ item: T) {
        items.append(item)
    }
    
    var count: Int {
        items.count
    }
    
    var values: [T] {
        items
    }
}

// MARK: - Test Helper Methods

/// Creates test resources with picsum.photos URLs
private func createTestResource(id: String, size: Int) -> Resource {
    let imageUrl = "https://picsum.photos/id/\(id)/\(size)/\(size)"
    return Resource(id: id,
                    main: FileMirror(id: id, location: imageUrl, info: [:]),
                    alternatives: [],
                    fileURL: nil)
}

/// Handles the download request, process, and completion waiting pattern
private func downloadAndWaitForCompletion(resource: Resource) async throws {
    // Create a ResourceManager with default cache implementation
    let cache = RealmCacheManager<CachedLocalFile>(configuration: Realm.Configuration(inMemoryIdentifier: "memory-identifier-123"))
    let manager = await ResourceManager.create(cache: cache)
    
    let requests = await manager.request(resources: [resource])
    
    guard let request = requests.first else { return }
    
    await manager.process(requests: requests)
    
    try await request.waitTillComplete()
}

/// Verifies a file URL points to a valid image file
private func verifyFileIsValidImage(at url: URL) throws {
    let data = try Data(contentsOf: url)
    guard let image = LocalImage(data: data) else {
        throw NSError(domain: "InvalidImageError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to create image from data"])
    }
    guard image.size.width > 0 && image.size.height > 0 else {
        throw NSError(domain: "InvalidImageError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Image has invalid dimensions"])
    }
}

// MARK: - FileManager Test Extensions

extension FileManager {
    var supportDirectoryURL: URL {
        return self.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
    
    var cacheDirectoryURL: URL {
        return self.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }
    
    static func createFileOnDisk() throws -> URL {
        let filename = FileManager.default.cacheDirectoryURL.appendingPathComponent(UUID().uuidString)

        // Create a small test file with emoji content
        try "😃".write(to: filename, atomically: true, encoding: String.Encoding.utf8)
        
        return filename
    }
}
