// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DownloadKit",
    platforms: [.iOS(.v12), .macOS(.v10_15)],
    products: [
        .library(
            name: "DownloadKit",
            targets: ["DownloadKit"]),
    ],
    dependencies: [
        .package(name: "Realm", url: "https://github.com/realm/realm-cocoa.git", .upToNextMajor(from: "5.0.0")),
    ],
    targets: [
        .target(
            name: "DownloadKit",
            dependencies: [
                .product(name: "RealmSwift", package: "Realm")
            ]),
        .testTarget(
            name: "DownloadKitTests",
            dependencies: [
                .target(name: "DownloadKit")
            ])
    ]
)
