// swift-tools-version: 6.0

import PackageDescription

// GPL-3.0-or-later. Formats and drivers ported from GPL-compatible sources (see README.md).
let package = Package(
    name: "GPSLoggerKitGPL",
    defaultLocalization: "en",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "GPSLoggerKitGPL", targets: ["GPSLoggerKitGPL"]),
    ],
    dependencies: [
        .package(path: "../GPSLoggerKit"),
    ],
    targets: [
        .target(
            name: "GPSLoggerKitGPL",
            dependencies: [.product(name: "GPSLoggerKit", package: "GPSLoggerKit")],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "GPSLoggerKitGPLTests",
            dependencies: ["GPSLoggerKitGPL", .product(name: "GPSLoggerKit", package: "GPSLoggerKit")],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
