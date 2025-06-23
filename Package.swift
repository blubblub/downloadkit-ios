// swift-tools-version:6.0
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
        .package(url: "https://github.com/realm/realm-swift.git", .upToNextMajor(from: "20.0.3")),
    ],
    targets: [
        .target(
            name: "DownloadKit",
            dependencies: [
                .product(name: "RealmSwift", package: "realm-swift")
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
