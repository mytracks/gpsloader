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
    targets: [
        .target(
            name: "LoggerCore",
            resources: [.process("Resources")]
        ),
        .target(name: "SerialTransport", dependencies: ["LoggerCore"]),
        .target(name: "GPSBabelRuntime", dependencies: ["LoggerCore"]),
        .target(name: "GPXExport", dependencies: ["LoggerCore"]),
        .target(name: "DiagnosticCapture", dependencies: ["LoggerCore"]),
        .target(name: "TestSupport", dependencies: ["LoggerCore", "DiagnosticCapture"]),

        .testTarget(name: "LoggerCoreTests", dependencies: ["LoggerCore", "TestSupport"]),
        .testTarget(name: "SerialTransportTests", dependencies: ["SerialTransport", "LoggerCore"]),
        .testTarget(name: "GPSBabelRuntimeTests", dependencies: ["GPSBabelRuntime", "LoggerCore", "TestSupport"]),
        .testTarget(
            name: "GPXExportTests",
            dependencies: ["GPXExport", "LoggerCore"],
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "DiagnosticCaptureTests",
            dependencies: ["DiagnosticCapture", "LoggerCore", "TestSupport"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "TestSupportTests", dependencies: ["TestSupport", "LoggerCore"]),
    ],
    swiftLanguageModes: [.v6]
)
