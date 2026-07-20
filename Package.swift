// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "testit-adapters-swift",
    platforms: [
        .iOS(.v14),
        .macOS(.v11),
        .tvOS(.v11),
        .watchOS(.v4),
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "testit-adapters-swift",
            targets: ["testit-adapters-swift"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Flight-School/AnyCodable", .upToNextMajor(from: "0.6.1")),
    ],
    targets: [
        .target(
            name: "AdaptersApi",
            dependencies: [
                .product(name: "AnyCodable", package: "AnyCodable"),
            ],
            path: "Sources/AdaptersApi",
            exclude: [
                // Contains `extension String: CodingKey` which conflicts in Swift 6 toolchains.
                // ExtensionsPatched.swift is the local replacement without that conformance.
                "Extensions.swift",
            ]
        ),
        .target(
            name: "testit-adapters-swift",
            dependencies: [
                "AdaptersApi",
            ],
            path: "Sources",
            exclude: [
                "AdaptersApi",
                // This file contains `extension String: CodingKey` which conflicts in Swift 6 toolchains.
                // We provide a local replacement without that conformance.
                "SyncStorage/SyncStorageClient/Extensions.swift",
            ]
        ),
    ]
)
