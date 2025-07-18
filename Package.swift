// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "testit-adapters-swift",
    platforms: [
        .iOS(.v11),
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
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/testit-tms/api-client-swift", .exact("0.3.1"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "testit-adapters-swift",
            dependencies: [
                .product(name: "testit-api-client", package: "api-client-swift")
            ],
            path: "Sources"
        ),
    ]
)
