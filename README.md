# DownloadKit

## Introduction

DownloadKit is a Swift library for managing file downloads in the background on Apple platforms. It supports multiple download sources – for example, standard HTTP(S) web servers as well as Apple’s CloudKit – and caches downloaded files locally for offline access. The library uses a priority-based queue system, allowing you to enqueue a large number of downloads (even thousands of files) and control the order in which they are fetched ￼. DownloadKit is used in production (e.g. in the Speech Blubs app) and is designed to handle robust, long-running download tasks reliably.

## Key features

• Background downloads: Uses background URL sessions and CloudKit operations so downloads can continue even if the app is suspended.

• Multiple sources: Unified interface to download from URLs or CloudKit (e.g. fetching CKAsset files from an iCloud database).

• Local caching: Files are stored locally once downloaded, avoiding redundant network fetches for the same resource.

• Priority queue: Each download can be assigned a priority. Higher-priority downloads will be executed first, ensuring important files download before less critical ones.

• Large batch support: The queue and cache management are optimized to handle many files at once (hundreds or thousands) without blocking your app’s UI.


## Installation

DownloadKit is distributed as a Swift Package. You can add it to your Xcode project or Swift package manifest using Swift Package Manager.
Swift Package Manager (SPM) via Xcode: In Xcode, select File > Add Packages… and enter the GitHub repository URL for DownloadKit:

`https://github.com/blubblub/downloadkit-ios`

Choose the latest release (e.g. 1.1.0) and add the package to your project. Xcode will handle fetching and integrating the package.

Swift Package Manager via Package.swift: If you use a Package.swift manifest, add DownloadKit as a dependency:

```swift
// In Package.swift
dependencies: [
    .package(url: "https://github.com/blubblub/downloadkit-ios.git", from: "1.1.0")
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
Now you’re ready to use the library in your app.

## Usage

Using DownloadKit typically involves three steps:
	1.	Create a Resource reference for each file you want to download (this could be an URL or a CloudKit record reference).
	2.	Enqueue the download using the shared download manager.
	3.	Handle completion or progress via a completion callback, delegate, or observer.

Below is an example of downloading a file from an URL:

```swift
import DownloadKit

// 1. Define the resource to download (from a URL in this case)
let fileURL = URL(string: "https://example.com/path/to/file.zip")!
let resource = ResourceFile(id: "example-file", url: fileURL, fileName: "file.zip")

// 2. Enqueue the download request via the ResourceManager
let requests = ResourceManager.shared.request(resources: [resource])
guard let downloadRequest = requests.first else {
    return  // No download started (perhaps already cached or invalid URL)
}

// 3. (Optional) Monitor or handle the download completion
// You could use an observer/delegate to get progress updates or, for simplicity, 
// poll the request’s state or use a completion handler if available.
downloadRequest.onCompletion = { result in
    switch result {
    case .success(let fileLocation):
        print("Download finished. File saved at: \(fileLocation.path)")
    case .failure(let error):
        print("Download failed with error: \(error)")
    }
}
```

# License

MIT License
