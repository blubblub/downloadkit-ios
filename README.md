# DownloadKit

## Introduction

DownloadKit is a Swift library for managing file downloads in the background on Apple platforms. Built with Swift tools version 6.0 and targeting Swift version 6.1.2, it supports multiple download sources like standard HTTP(S) web servers and Apple’s CloudKit. Files are cached locally for offline access. The priority-based queue system allows enqueuing numerous downloads efficiently. It's used in production scenarios, such as in the Speech Blubs app, and designed for robust, long-running download tasks.

## Key features

• Background downloads: Uses background URL sessions and CloudKit operations so downloads can continue even if the app is suspended.

• Multiple sources: Unified interface to download from URLs or CloudKit (e.g., fetching CKAsset files from an iCloud database) with improved error handling and mirroring.

• Local caching: Files are stored locally once downloaded, avoiding redundant network fetches for the same resource.

• Priority queue: Each download can be assigned a priority. Higher-priority downloads will be executed first, ensuring important files download before less critical ones.

• Large batch support: The queue and cache management are optimized to handle many files at once (hundreds or thousands) without blocking your app’s UI.


## Installation

DownloadKit is distributed as a Swift Package. Platforms supported include iOS 15 and macOS 12. Add it to your Xcode project or Swift package manifest via Swift Package Manager.
Swift Package Manager (SPM) via Xcode: In Xcode, select File > Add Packages… and enter the GitHub repository URL for DownloadKit:

`https://github.com/blubblub/downloadkit-ios`

Choose the latest release available in the repository and add the package to your project. Xcode will handle fetching and integrating the package.

Swift Package Manager via Package.swift: If you use a Package.swift manifest, add DownloadKit as a dependency:

```swift
// In Package.swift
dependencies: [
    .package(url: "https://github.com/blubblub/downloadkit-ios.git", from: "1.0.0")
],
…
targets: [
    .target(
        name: "<YourTargetName>",
        dependencies: [
            .product(name: "DownloadKit", package: "downloadkit-ios")
        ]
    )
]
```

After adding the package, run `swift build` or use Xcode’s build to fetch the dependency. Then import DownloadKit in your Swift code:

```swift
import DownloadKit
```
Now you're ready to use the library in your app.

## Package Architecture

DownloadKit is split into two main components:

### DownloadKitCore
The core functionality that handles:
- Download queue management and prioritization
- Download processors (Web, CloudKit)
- Resource and mirror abstractions
- Error handling, including DownloadKitError
- Progress tracking and metrics
- Basic caching protocols

**Dependencies**: Only Foundation and system frameworks (URLSession, CloudKit)

### DownloadKitRealm
Realm-based implementation for local file cache tracking:
- Persistent storage of download metadata
- File location tracking and cache management
- Default ResourceManager convenience methods
- Local file deduplication and cleanup

**Dependencies**: RealmSwift for local database operations

### Importing Components

You can import either the complete package or individual components:

```swift
// Import everything (recommended for most users)
import DownloadKit

// Or import only specific components
import DownloadKitCore     // Core download functionality only
import DownloadKitRealm    // Realm-based cache + convenience methods
```

**Note**: The `ResourceManager.default()` setup is now async and provides caching using Realm by default. If you import only DownloadKitCore, you must manually configure your ResourceManager with a custom cache and processor setup.

## Usage

DownloadKit uses modern Swift concurrency (async/await) and provides a resource-based API. Using DownloadKit typically involves:

1. Creating a Resource with one or more mirror locations for each file you want to download.
2. Enqueuing the download using the ResourceManager (async).
3. Handling completion via completion callbacks or observers.

### Basic Web Download

Below is an example of downloading a file from a web URL:

```swift
import DownloadKit

// 1. Create a mirror for the file location
let mirror = FileMirror(
    id: "mirror-1",
    location: "https://example.com/path/to/file.zip",
    info: [:]
)

// 2. Create a resource with the mirror
let resource = Resource(
    id: "example-file",
    main: mirror,
    alternatives: [],  // Optional alternative mirrors
    fileURL: nil,
    createdAt: nil
)

// 3. Get default resource manager and request the download
Task {
    let resourceManager = await ResourceManager.default()
    
    let requests = await resourceManager.request(
        resources: [resource],
        options: RequestOptions(downloadPriority: .normal, storagePriority: .cached)
    )
    
    guard let downloadRequest = requests.first else {
        return  // No download started (already cached or invalid)
    }
    
    // 4. (Optional) Add completion callback
    await resourceManager.addResourceCompletion(for: resource) { success, identifier in
        if success {
            print("Download completed for: \(identifier)")
        } else {
            print("Download failed for: \(identifier)")
        }
    }
    
    // 5. Process the download request to start downloading
    await resourceManager.process(request: downloadRequest)
    
    // 6. Resume downloads (if needed)
    await resourceManager.resume()
}
```

### Advanced Usage with Multiple Mirrors

DownloadKit supports multiple mirror locations for redundancy:

```swift
import DownloadKit

// Create multiple mirrors for redundancy
let primaryMirror = FileMirror(
    id: "primary",
    location: "https://cdn1.example.com/file.zip",
    info: ["weight": 1]
)

let backupMirror = FileMirror(
    id: "backup",
    location: "https://cdn2.example.com/file.zip",
    info: ["weight": 2]
)

let resource = Resource(
    id: "redundant-file",
    main: primaryMirror,
    alternatives: [backupMirror]
)

Task {
    let resourceManager = await ResourceManager.default()
    
    let requests = await resourceManager.request(
        resources: [resource],
        options: RequestOptions(downloadPriority: .high, storagePriority: .permanent)
    )
    
    // Process the downloads with high priority
    await resourceManager.process(requests: requests, priority: .high)
    await resourceManager.resume()
}
```

### CloudKit Downloads

DownloadKit also supports CloudKit asset downloads:

```swift
// CloudKit resource
let cloudKitMirror = FileMirror(
    id: "cloudkit-mirror",
    location: "cloudkit://database/record/asset",
    info: [:]
)

let cloudResource = Resource(
    id: "cloud-file",
    main: cloudKitMirror
)

Task {
    let resourceManager = await ResourceManager.default()
    let requests = await resourceManager.request(resources: [cloudResource])
    await resourceManager.process(requests: requests)
    await resourceManager.resume()
}
```

### DownloadProcessors

DownloadKit uses a modular processor architecture. **DownloadProcessors** are responsible for handling the actual download logic for different types of resources (web URLs, CloudKit assets, etc.). Each processor knows how to handle specific download types:

- **WebDownloadProcessor**: Handles HTTP/HTTPS downloads using URLSession
- **CloudKitDownloadProcessor**: Handles CloudKit CKAsset downloads
- Custom processors can be created by implementing the `DownloadProcessor` protocol

### Resource Manager Setup

**Quick Start**: For most use cases, you can use the convenient default setup:

```swift
let resourceManager = await ResourceManager.default()
```

This creates a ResourceManager with:
- Realm-based cache using the default configuration
- WebDownloadProcessor for HTTP/HTTPS downloads
- Proper async setup

**Custom Setup**: For advanced use cases, you can manually configure a ResourceManager with:
1. A cache implementation
2. DownloadQueues configured with the appropriate DownloadProcessors

```swift
import DownloadKit

Task {
    // 1. Set up download queues with processors
    let downloadQueue = DownloadQueue()
    await downloadQueue.add(processor: WebDownloadProcessor())  // For web downloads
    await downloadQueue.add(processor: CloudKitDownloadProcessor())  // For CloudKit downloads
    
    // 2. (Optional) Set up a priority queue for high-priority downloads
    let priorityQueue = DownloadQueue()
    await priorityQueue.add(processor: WebDownloadProcessor.priorityProcessor())
    await priorityQueue.add(processor: CloudKitDownloadProcessor())
    
    // 3. Set up cache (using Realm-based cache)
    let cache = RealmCacheManager<CachedLocalFile>()
    
    // 4. Create resource manager
    let resourceManager = ResourceManager(
        cache: cache,
        downloadQueue: downloadQueue,
        priorityQueue: priorityQueue  // optional
    )
    
    // 5. Start the manager
    await resourceManager.resume()
}
```

### Processor Configuration

You can customize processors during setup:

```swift
// Custom web processor with specific URLSession configuration
let customConfig = URLSessionConfiguration.background(withIdentifier: "my-app-downloads")
customConfig.allowsCellularAccess = false  // WiFi only
let webProcessor = WebDownloadProcessor(configuration: customConfig)

// CloudKit processor with specific database
let container = CKContainer(identifier: "iCloud.com.yourapp.container")
let cloudKitProcessor = CloudKitDownloadProcessor(database: container.publicCloudDatabase)

Task {
    let downloadQueue = DownloadQueue()
    await downloadQueue.add(processor: webProcessor)
    await downloadQueue.add(processor: cloudKitProcessor)
    
    // Continue with ResourceManager setup...
}
```

# License

Please refer to the project's license file for licensing information.
