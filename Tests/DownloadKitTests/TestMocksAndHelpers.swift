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
    
    func setDidFinishCallback(_ callback: @escaping (DownloadTask, Downloadable, URL) -> Void) {
        didFinishCallback = callback
    }
    
    func setDidStartCallback(_ callback: @escaping (DownloadTask, Downloadable, DownloadProcessor) -> Void) {
        didStartCallback = callback
    }
    
    func setDidTransferDataCallback(_ callback: @escaping (DownloadTask, Downloadable, DownloadProcessor) -> Void) {
        didTransferDataCallback = callback
    }
    
    func setDidRetryCallback(_ callback: @escaping (DownloadTask, DownloadRetryContext) -> Void) {
        didRetryCallback = callback
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
        let identifier = self.identifier
        let url = self.url
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
                        alternatives: (1...mirrorCount).map { FileMirror.random(weight: $0) })
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

/// Enum representing different file sizes for test resources
public enum TestFileSize: Sendable {
    case tiny         // ~100KB (picsum.photos image)
    case small        // ~1MB
    case medium       // ~5MB
    case large        // ~10MB
    case extraLarge   // ~25MB
    case huge         // ~50MB
    
    /// Returns the URL for the test file of this size
    var url: String {
        switch self {
        case .tiny:
            return "https://picsum.photos/100/100.jpg"
        case .small:
            return "https://proof.ovh.net/files/1Mb.dat"
        case .medium:
            return "http://ipv4.download.thinkbroadband.com/5MB.zip"
        case .large:
            return "https://proof.ovh.net/files/10Mb.dat"
        case .extraLarge:
            return "https://serc.carleton.edu/download/files/91151/unit_5_google_earth.zip"
        case .huge:
            return "http://ipv4.download.thinkbroadband.com/50MB.zip"
        }
    }
    
    /// Returns the approximate size in bytes
    var approximateBytes: Int64 {
        switch self {
        case .tiny:
            return 100_000 // ~100KB
        case .small:
            return 1_048_576 // 1MB
        case .medium:
            return 5_242_880 // 5MB
        case .large:
            return 10_485_760 // 10MB
        case .extraLarge:
            return 26_214_400 // 25MB
        case .huge:
            return 52_428_800 // 50MB
        }
    }
    
    /// Returns a human-readable description of the file size
    var description: String {
        switch self {
        case .tiny:
            return "~100KB"
        case .small:
            return "~1MB"
        case .medium:
            return "~5MB"
        case .large:
            return "~10MB"
        case .extraLarge:
            return "~25MB"
        case .huge:
            return "~50MB"
        }
    }
}

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
        alternatives: []
    )
}

/// Creates a test resource with a specific file size for testing
/// - Parameters:
///   - id: The resource identifier
///   - fileSize: The desired file size category
/// - Returns: A test Resource instance
func createTestResource(id: String, fileSize: TestFileSize) -> Resource {
    return Resource(
        id: id,
        main: FileMirror(
            id: "mirror-\(id)",
            location: fileSize.url,
            info: ["expectedSize": fileSize.approximateBytes]
        ),
        alternatives: []
    )
}

/// Creates test resources using free online APIs for integration testing
func createTestResources(count: Int, size: Int = 100) -> [Resource] {
    return (1...count).map { i in
        return createTestResource(
            id: "integration-resource-\(i)",
            size: size
        )
    }
}

/// Creates test resources with specific file sizes for integration testing
/// - Parameters:
///   - count: Number of resources to create
///   - fileSize: The desired file size category for all resources
/// - Returns: Array of test Resource instances
func createTestResources(count: Int, fileSize: TestFileSize) -> [Resource] {
    return (1...count).map { i in
        return createTestResource(
            id: "integration-resource-\(fileSize.description)-\(i)",
            fileSize: fileSize
        )
    }
}

/// Creates test resources with mixed file sizes for integration testing
/// - Parameters:
///   - count: Number of resources to create
///   - fileSizes: Array of file sizes to cycle through
/// - Returns: Array of test Resource instances
func createTestResources(count: Int, fileSizes: [TestFileSize]) -> [Resource] {
    guard !fileSizes.isEmpty else {
        return createTestResources(count: count) // Fallback to default
    }
    
    return (1...count).map { i in
        let fileSize = fileSizes[(i - 1) % fileSizes.count]
        return createTestResource(
            id: "integration-resource-mixed-\(i)",
            fileSize: fileSize
        )
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
func setupManagerWithPriorityQueue(simultaneousDownloads: Int = 4, priorityDownloads: Int = 10) async -> (ResourceManager, RealmCacheManager<CachedLocalFile>, Realm) {
    let downloadQueue = DownloadQueue()
    await downloadQueue.set(simultaneousDownloads: simultaneousDownloads)
    await downloadQueue.add(processor: WebDownloadProcessor(configuration: .default))
    
    // Create priority queue for high and urgent priority downloads
    let priorityQueue = DownloadQueue()
    await priorityQueue.set(simultaneousDownloads: priorityDownloads)
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
                 ])
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
