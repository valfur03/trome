// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TROMECore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "TROMECore", targets: ["TROMECore"]),
        .library(name: "TROMEBadge", targets: ["TROMEBadge"])
    ],
    targets: [
        .target(name: "TROMECore", resources: [.copy("Resources/stations.json")]),
        .testTarget(name: "TROMECoreTests", dependencies: ["TROMECore"]),
        // The line badges are drawn by SwiftUI, which TROMECore must not import; they get their own module so that
        // the app and the widget share one badge, and its test draws every badge on the Mac.
        .target(name: "TROMEBadge", dependencies: ["TROMECore"]),
        .testTarget(name: "TROMEBadgeTests", dependencies: ["TROMEBadge"])
    ]
)
