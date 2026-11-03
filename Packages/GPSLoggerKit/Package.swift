// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GPSLoggerKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v12), .iOS("27.0")],
    products: [
        .library(name: "GPSLoggerKit", targets: ["GPSLoggerKit"]),
    ],
    targets: [
        .target(
            name: "GPSLoggerKit",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "GPSLoggerKitTests",
            dependencies: ["GPSLoggerKit"],
            resources: [.copy("Fixtures"), .copy("Schemas")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
