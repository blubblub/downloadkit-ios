//
//  TestMocksAndHelpers.swift
//  DownloadKitTests
//
//  This file consolidates all mock resources, factory functions, and test utilities
//  extracted from various test files in the DownloadKit test suite.
//

import Foundation
import XCTest
import Realm
import RealmSwift
@testable import DownloadKit
@testable import DownloadKitRealm

// MARK: - Helper Actors

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

// MARK: - Mock Delegates

/// Mock implementation of MirrorPolicyDelegate for testing
class MockPolicyDelegate: MirrorPolicyDelegate, @unchecked Sendable {
    
    private var _exhaustedAllMirrors = false
    private var _failedToGenerateDownloadable = false
    private let lock = NSLock()
    
    var exhaustedAllMirrors: Bool {
        get {
            lock.withLock { _exhaustedAllMirrors }
        }
        set {
            lock.withLock { _exhaustedAllMirrors = newValue }
        }
    }
    
    var failedToGenerateDownloadable: Bool {
        get {
            lock.withLock { _failedToGenerateDownloadable }
        }
        set {
            lock.withLock { _failedToGenerateDownloadable = newValue }
        }
    }
    
    func mirrorPolicy(_ mirrorPolicy: MirrorPolicy, didExhaustMirrorsIn file: ResourceFile) {
        exhaustedAllMirrors = true
    }
    
    func mirrorPolicy(_ mirrorPolicy: MirrorPolicy, didFailToGenerateDownloadableIn file: ResourceFile, for mirror: ResourceFileMirror) {
        failedToGenerateDownloadable = true
    }
}

// MARK: - Mock Observers

/// Mock implementation of DownloadProcessorObserver for testing download events
actor DownloadProcessorObserverMock: DownloadProcessorObserver {
    var beginCallback: (() -> Void)?
    var startTransferCallback: (() -> Void)?
    var errorCallback: ((Error) -> Void)?
    var finishTransferCallback: ((URL) -> Void)?
    var finishCallback: (() -> Void)?
    
    func setBeginCallback(_ callback: @Sendable @escaping () -> Void) {
        beginCallback = callback
    }
    
    func setStartTransferCallback(_ callback: @Sendable @escaping () -> Void) {
        startTransferCallback = callback
    }
    
    func setErrorCallback(_ callback: @Sendable @escaping (Error) -> Void) {
        errorCallback = callback
    }
    
    func setFinishTransferCallback(_ callback: @Sendable @escaping (URL) -> Void) {
        finishTransferCallback = callback
    }
    
    func setFinishCallback(_ callback: @Sendable @escaping () -> Void) {
        finishCallback = callback
    }
    
    func downloadDidBegin(_ processor: DownloadProcessor, downloadable: Downloadable) {
        beginCallback?()
    }
    
    // Should be sent when a Downloadable starts transferring data.
    func downloadDidStartTransfer(_ processor: DownloadProcessor, downloadable: Downloadable) {
        startTransferCallback?()
    }
    
    // Should be sent when a Downloadable fails for any reason.
    func downloadDidError(_ processor: DownloadProcessor, downloadable: Downloadable, error: Error) {
        errorCallback?(error)
    }
    
    // Should be sent when a Downloadable finishes transferring data.
    func downloadDidFinishTransfer(_ processor: DownloadProcessor, downloadable: Downloadable, to url: URL) {
        finishTransferCallback?(url)
    }
    
    // Should be sent when a Downloadable is completely finished.
    func downloadDidFinish(_ processor: DownloadProcessor, downloadable: Downloadable) {
        finishCallback?()
    }

    func downloadDidTransferData(_ processor: any DownloadKit.DownloadProcessor, downloadable: any DownloadKit.Downloadable) {
    }
}

/// Mock implementation of DownloadQueueObserver for testing download queue events
actor DownloadQueueObserverMock: DownloadQueueObserver {
    var didStartCallback: ((DownloadTask, Downloadable, DownloadProcessor) -> Void)?
    var didTransferDataCallback: ((DownloadTask, Downloadable, DownloadProcessor) -> Void)?
    var didFinishCallback: ((DownloadTask, Downloadable, URL) -> Void)?
    var didFailCallback: ((DownloadTask, Error) -> Void)?
    var didRetryCallback: ((DownloadTask, DownloadRetryContext) -> Void)?
    
    func downloadQueue(_ queue: DownloadQueue, downloadDidStart downloadTask: DownloadTask, downloadable: Downloadable, on processor: DownloadProcessor) async {
        didStartCallback?(downloadTask, downloadable, processor)
    }
    
    func downloadQueue(_ queue: DownloadQueue, downloadDidTransferData downloadTask: DownloadTask, downloadable: Downloadable, using processor: DownloadProcessor) async {
        didTransferDataCallback?(downloadTask, downloadable, processor)
    }
    
    func downloadQueue(_ queue: DownloadQueue, downloadDidFinish downloadTask: DownloadTask, downloadable: Downloadable, to location: URL) async throws {
        didFinishCallback?(downloadTask, downloadable, location)
    }
    
    func downloadQueue(_ queue: DownloadQueue, downloadDidFail downloadTask: DownloadTask, with error: Error) async {
        didFailCallback?(downloadTask, error)
    }
    
    func downloadQueue(_ queue: DownloadQueue, downloadWillRetry downloadTask: DownloadTask, context: DownloadRetryContext) async {
        didRetryCallback?(downloadTask, context)
    }
    
    func setDidFailCallback(_ callback: @escaping (DownloadTask, Error) -> Void) {
        didFailCallback = callback
    }
}

// MARK: - Resource Factory Extensions

public extension FileMirror {
    /// Creates a random FileMirror with the specified weight for testing
    static func random(weight: Int) -> FileMirror {
        FileMirror(id: UUID().uuidString,
                   location: "https://example.com/file",
                   info: [WeightedMirrorPolicy.weightKey: weight])
    }
}

/// Extension to convert WebDownload to FileMirror for testing
extension WebDownload {
    func toMirror() async -> FileMirror {
        let identifier = await self.identifier
        let url = await self.url
        return FileMirror(
            id: identifier,
            location: url.absoluteString,
            info: [:]
        )
    }
}

public extension Resource {
    /// Creates a sample Resource with the specified number of alternative mirrors
    static func sample(mirrorCount: Int) -> Resource {
        return Resource(id: "sample-id",
                        main: FileMirror.random(weight: 0),
                        alternatives: (1...mirrorCount).map { FileMirror.random(weight: $0) },
                        fileURL: nil)
    }
}

// MARK: - FileManager Test Extensions

extension FileManager {
    /// Returns the Application Support directory URL
    var supportDirectoryURL: URL {
        return self.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
    
    /// Returns the Caches directory URL
    var cacheDirectoryURL: URL {
        return self.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }
    
    /// Creates a temporary file on disk with emoji content for testing
    static func createFileOnDisk() throws -> URL {
        let filename = FileManager.default.cacheDirectoryURL.appendingPathComponent(UUID().uuidString)

        // Create a small test file with emoji content
        try "😃".write(to: filename, atomically: true, encoding: String.Encoding.utf8)
        
        return filename
    }
}

// MARK: - Resource Creation Factory Methods

/// Creates a test resource with picsum.photos URLs for testing
/// - Parameters:
///   - id: The resource identifier
///   - size: The image size (width and height), defaults to 100
/// - Returns: A test Resource instance
func createTestResource(id: String, size: Int = 100) -> Resource {
    return Resource(
        id: id,
        main: FileMirror(
            id: "mirror-\(id)",
            location: "https://picsum.photos/\(size)/\(size).jpg", // Small image for faster tests
            info: [:]
        ),
        alternatives: [],
        fileURL: nil
    )
}

/// Creates test resources using free online APIs for integration testing
func createTestResources(count: Int) -> [Resource] {
    return (1...count).map { i in
        // Use reliable small image service
        let imageSize = 50 + (i % 5) * 10 // 50x50, 60x60, 70x70, 80x80, 90x90
        let selectedURL = "https://picsum.photos/\(imageSize)/\(imageSize).jpg"
        
        return Resource(
            id: "integration-resource-\(i)",
            main: FileMirror(
                id: "mirror-\(i)",
                location: selectedURL,
                info: [:]
            ),
            alternatives: [],
            fileURL: nil
        )
    }
}

/// Creates a test resource for storage testing
func createTestResourceForStorage(id: String) -> Resource {
    return Resource(
        id: id,
        main: FileMirror(
            id: "mirror-\(id)",
            location: "https://picsum.photos/80/80.jpg", // Small image for faster tests
            info: [:]
        ),
        alternatives: [],
        fileURL: nil
    )
}

/// Creates test WebDownload instances for download queue testing
func createTestDownloads(count: Int) -> [WebDownload] {
    return (0..<count).map { index in
        WebDownload(identifier: "test-download-\(index)", 
                   url: URL(string: "https://example.com/file\(index)")!)
    }
}

// MARK: - Download Process Helper Methods

/// Handles the download request, process, and completion waiting pattern
func downloadAndWaitForCompletion(resource: Resource) async throws {
    // Create a ResourceManager with default cache implementation
    let cache = RealmCacheManager<CachedLocalFile>(configuration: Realm.Configuration(inMemoryIdentifier: "memory-identifier-123"))
    let manager = ResourceManager.create(cache: cache)
    
    let requests = await manager.request(resources: [resource])
    
    guard let request = requests.first else { return }
    
    let tasks = await manager.process(requests: requests)
    guard let task = tasks.first else { return }
    
    try await task.waitTillComplete()
}

/// Verifies a file URL points to a valid image file
func verifyFileIsValidImage(at url: URL) throws {
    let data = try Data(contentsOf: url)
    guard let image = LocalImage(data: data) else {
        throw NSError(domain: "InvalidImageError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to create image from data"])
    }
    guard image.size.width > 0 && image.size.height > 0 else {
        throw NSError(domain: "InvalidImageError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Image has invalid dimensions"])
    }
}

// MARK: - Manager Setup Helper Methods

/// Creates a ResourceManager with standard configuration using async/await patterns
/// Uses in-memory Realm configuration to avoid test conflicts
func setupManager() async -> (ResourceManager, RealmCacheManager<CachedLocalFile>, Realm) {
    let downloadQueue = DownloadQueue()
    await downloadQueue.add(processor: WebDownloadProcessor(configuration: .default))
    
    // Use in-memory configuration to avoid cache conflicts
    let config = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
    
    // Create Realm instance and keep it alive during the test
    let realm = try! await Realm(configuration: config, actor: MainActor.shared)
    
    let cache = RealmCacheManager<CachedLocalFile>(configuration: config)
    let manager = ResourceManager(cache: cache, downloadQueue: downloadQueue)
    
    return (manager, cache, realm)
}

/// Creates a ResourceManager with both normal and priority queues using async/await patterns
/// Uses in-memory Realm configuration to avoid test conflicts
func setupWithPriorityQueue() async -> (ResourceManager, RealmCacheManager<CachedLocalFile>, Realm) {
    let downloadQueue = DownloadQueue()
    await downloadQueue.add(processor: WebDownloadProcessor(configuration: .default))
    
    let priorityQueue = DownloadQueue()
    await priorityQueue.add(processor: WebDownloadProcessor.priorityProcessor())
    
    // Use in-memory configuration to avoid cache conflicts
    let config = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
    
    // Create Realm instance and keep it alive during the test
    let realm = try! await Realm(configuration: config, actor: MainActor.shared)
    
    let cache = RealmCacheManager<CachedLocalFile>(configuration: config)
    let manager = ResourceManager(cache: cache, downloadQueue: downloadQueue, priorityQueue: priorityQueue)
    
    return (manager, cache, realm)
}

/// Helper method to setup ResourceManager with priority queue for priority tests
func setupManagerWithPriorityQueue() async -> (ResourceManager, RealmCacheManager<CachedLocalFile>, Realm) {
    let downloadQueue = DownloadQueue()
    await downloadQueue.set(simultaneousDownloads: 4)
    await downloadQueue.add(processor: WebDownloadProcessor(configuration: .default))
    
    // Create priority queue for high and urgent priority downloads
    let priorityQueue = DownloadQueue()
    await priorityQueue.add(processor: WebDownloadProcessor(configuration: WebDownloadProcessor.priorityConfiguration(configuration: .default)))
    
    // Use in-memory Realm configuration
    let config = Realm.Configuration(
        inMemoryIdentifier: "priority_test_realm_\(UUID().uuidString)",
        deleteRealmIfMigrationNeeded: true
    )
    
    // Create Realm instance and keep it alive during the test
    let realm = try! await Realm(configuration: config, actor: MainActor.shared)
    
    let cache = RealmCacheManager<CachedLocalFile>(configuration: config)
    let manager = ResourceManager(cache: cache, downloadQueue: downloadQueue, priorityQueue: priorityQueue)
    
    return (manager, cache, realm)
}

/// Helper method to setup ResourceManager without priority queue (normal priority only)
func setupManagerWithoutPriorityQueue() async -> (ResourceManager, RealmCacheManager<CachedLocalFile>, Realm) {
    let downloadQueue = DownloadQueue()
    await downloadQueue.add(processor: WebDownloadProcessor(configuration: .default))
    
    // Use in-memory Realm configuration
    let config = Realm.Configuration(
        inMemoryIdentifier: "normal_test_realm_\(UUID().uuidString)",
        deleteRealmIfMigrationNeeded: true
    )
    
    // Create Realm instance and keep it alive during the test
    let realm = try! await Realm(configuration: config, actor: MainActor.shared)
    
    let cache = RealmCacheManager<CachedLocalFile>(configuration: config)
    let manager = ResourceManager(cache: cache, downloadQueue: downloadQueue) // No priority queue
    
    return (manager, cache, realm)
}

/// Helper method to setup ResourceManager for integration tests
func setupManagerForIntegrationTests() async -> (ResourceManager, RealmCacheManager<CachedLocalFile>, Realm) {
    let downloadQueue = DownloadQueue()
    // Use default configuration for tests - ephemeral has delegate callback issues in iOS Simulator
    await downloadQueue.add(processor: WebDownloadProcessor(configuration: .default))
    
    // Use in-memory Realm for testing to avoid conflicts
    let config = Realm.Configuration(inMemoryIdentifier: "integration-test-\(UUID().uuidString)")
    
    // Create Realm instance and keep it alive during the test
    let realm = try! await Realm(configuration: config, actor: MainActor.shared)
    
    let cache = RealmCacheManager<CachedLocalFile>(configuration: config)
    let manager = ResourceManager(cache: cache, downloadQueue: downloadQueue)
    
    return (manager, cache, realm)
}

/// Helper method to setup ResourceManager for storage tests
func setupManagerForStorageTests() async -> (ResourceManager, RealmCacheManager<CachedLocalFile>, Realm) {
    let downloadQueue = DownloadQueue()
    await downloadQueue.add(processor: WebDownloadProcessor(configuration: .default))
    
    // Use in-memory Realm configuration
    let config = Realm.Configuration(
        inMemoryIdentifier: "test_realm_\(UUID().uuidString)"
    )
    
    // Create Realm instance and keep it alive during the test, so it does not delete data
    // during instances being opened.
    let realm = try! await Realm(configuration: config, actor: MainActor.shared)
    
    let cache = RealmCacheManager<CachedLocalFile>(configuration: config)
    let manager = ResourceManager(cache: cache, downloadQueue: downloadQueue)
    
    return (manager, cache, realm)
}

// MARK: - Test Resource Collections

/// Returns a collection of resources for basic testing
var testResources: [Resource] {
    let resources = [
        Resource(id: "resource-id",
                 main: FileMirror(id: "resource-id", location: "https://picsum.photos/10", info: [:]),
                 alternatives: [
                   FileMirror(id: "resource-id", location: "https://picsum.photos/100", info: [WeightedMirrorPolicy.weightKey: 100]),
                   FileMirror(id: "resource-id", location: "https://picsum.photos/50", info: [WeightedMirrorPolicy.weightKey: 50])
                 ],
                 fileURL: nil)
    ]
    
    return resources
}

// MARK: - Validation Helper Methods

/// Validates that a resource has been successfully cached
func validateResourceIsCached(resource: Resource, cache: RealmCacheManager<CachedLocalFile>) -> Bool {
    guard let cachedURL = cache.fileURL(for: resource.id) else {
        return false
    }
    return FileManager.default.fileExists(atPath: cachedURL.path)
}

/// Validates that a file is stored in the cache directory
func validateFileIsInCacheDirectory(url: URL) -> Bool {
    let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    return url.path.hasPrefix(cacheDirectory.path)
}

/// Validates that a file is stored in permanent storage (Application Support)
func validateFileIsInPermanentStorage(url: URL) -> Bool {
    let isPermanentLocation = url.path.contains("Application Support") ||
                             (!url.path.contains("Caches") && !url.path.contains("cache"))
    return isPermanentLocation
}

// MARK: - Test Expectation Helpers

/// Creates and configures a batch download expectation
func createBatchDownloadExpectation(count: Int, description: String = "Batch downloads should complete") -> XCTestExpectation {
    let expectation = XCTestExpectation(description: description)
    expectation.expectedFulfillmentCount = count
    return expectation
}

/// Sets up completion tracking for a collection of resources
func setupCompletionTracking(for resources: [Resource], 
                              manager: ResourceManager,
                              expectation: XCTestExpectation,
                              successCounter: ActorCounter,
                              failureCounter: ActorCounter) async {
    for resource in resources {
        await manager.addResourceCompletion(for: resource) { @Sendable (success, resourceID) in
            Task {
                if success {
                    await successCounter.increment()
                } else {
                    await failureCounter.increment()
                }
                expectation.fulfill()
            }
        }
    }
}