// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DownloadKit",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(
            name: "DownloadKit",
            targets: ["DownloadKit"]),
        .library(
            name: "DownloadKitCore",
            targets: ["DownloadKitCore"]),
        .library(
            name: "DownloadKitRealm",
            targets: ["DownloadKitRealm"]),
    ],
    dependencies: [
        .package(url: "https://github.com/realm/realm-swift.git", .upToNextMajor(from: "20.0.3")),
    ],
    targets: [
        .target(
            name: "DownloadKitCore",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]),
        .target(
            name: "DownloadKitRealm",
            dependencies: [
                .target(name: "DownloadKitCore"),
                .product(name: "RealmSwift", package: "realm-swift")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]),
        .target(
            name: "DownloadKit",
            dependencies: [
                .target(name: "DownloadKitCore"),
                .target(name: "DownloadKitRealm")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
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
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
