// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DownloadKit",
    platforms: [
        .iOS(.v14),
        .macOS(.v10_15),
        .watchOS(.v5)
    ],
    products: [
        .library(
            name: "DownloadKit",
            targets: ["DownloadKit"]),
    ],
    dependencies: [
        .package(name: "Realm", url: "https://github.com/realm/realm-swift.git", .upToNextMajor(from: "10.18.0")),
    ],
    targets: [
        .target(
            name: "DownloadKit",
            dependencies: [
                .product(name: "RealmSwift", package: "Realm")
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-enable-upcoming-feature", "StrictConcurrency",
                    "-enable-upcoming-feature", "ConciseMagicFile",
                    "-Xfrontend", "-warn-concurrency",
                    "-Xfrontend", "-enable-actor-data-race-checks"
                ])
            ]),
        .testTarget(
            name: "DownloadKitTests",
            dependencies: [
                .target(name: "DownloadKit")
            ],
            resources: [
                .process("Data")
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-enable-upcoming-feature", "StrictConcurrency",
                    "-enable-upcoming-feature", "ConciseMagicFile",
                    "-Xfrontend", "-warn-concurrency",
                    "-Xfrontend", "-enable-actor-data-race-checks"
                ])
            ])
    ]
)
