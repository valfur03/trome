// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RATPCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "RATPCore", targets: ["RATPCore"])
    ],
    targets: [
        .target(name: "RATPCore"),
        .testTarget(name: "RATPCoreTests", dependencies: ["RATPCore"])
    ]
)
