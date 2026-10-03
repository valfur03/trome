// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TROMECore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "TROMECore", targets: ["TROMECore"])
    ],
    targets: [
        .target(name: "TROMECore", resources: [.copy("Resources/stations.json")]),
        .testTarget(name: "TROMECoreTests", dependencies: ["TROMECore"])
    ]
)
