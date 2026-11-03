// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GPSLoaderKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "LoggerCore", targets: ["LoggerCore"]),
        .library(name: "SerialTransport", targets: ["SerialTransport"]),
        .library(name: "GPSBabelRuntime", targets: ["GPSBabelRuntime"]),
        .library(name: "GPXExport", targets: ["GPXExport"]),
        .library(name: "DiagnosticCapture", targets: ["DiagnosticCapture"]),
        .library(name: "TestSupport", targets: ["TestSupport"]),
    ],
    dependencies: [
        .package(path: "../GPSLoggerKit"),
    ],
    targets: [
        .target(
            name: "LoggerCore",
            dependencies: [.product(name: "GPSLoggerKit", package: "GPSLoggerKit")],
            resources: [.process("Resources")]
        ),
        .target(name: "SerialTransport", dependencies: ["LoggerCore"]),
        .target(name: "GPSBabelRuntime", dependencies: ["LoggerCore"]),
        .target(name: "GPXExport", dependencies: ["LoggerCore", .product(name: "GPSLoggerKit", package: "GPSLoggerKit")]),
        .target(name: "DiagnosticCapture", dependencies: ["LoggerCore"]),
        .target(
            name: "TestSupport",
            dependencies: ["LoggerCore", "DiagnosticCapture", .product(name: "GPSLoggerKit", package: "GPSLoggerKit")]
        ),

        .testTarget(
            name: "LoggerCoreTests",
            dependencies: ["LoggerCore", "TestSupport", .product(name: "GPSLoggerKit", package: "GPSLoggerKit")]
        ),
        .testTarget(name: "SerialTransportTests", dependencies: ["SerialTransport", "LoggerCore"]),
        .testTarget(name: "GPSBabelRuntimeTests", dependencies: ["GPSBabelRuntime", "LoggerCore", "TestSupport"]),
        .testTarget(
            name: "GPXExportTests",
            dependencies: ["GPXExport", "LoggerCore", .product(name: "GPSLoggerKit", package: "GPSLoggerKit")]
        ),
        .testTarget(
            name: "DiagnosticCaptureTests",
            dependencies: ["DiagnosticCapture", "LoggerCore", "TestSupport", .product(name: "GPSLoggerKit", package: "GPSLoggerKit")],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "TestSupportTests", dependencies: ["TestSupport", "LoggerCore"]),
    ],
    swiftLanguageModes: [.v6]
)
