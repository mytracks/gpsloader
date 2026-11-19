// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GPSLoaderKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "LoggerCore", targets: ["LoggerCore"]),
        .library(name: "SerialTransport", targets: ["SerialTransport"]),
        .library(name: "GPXExport", targets: ["GPXExport"]),
        .library(name: "DiagnosticCapture", targets: ["DiagnosticCapture"]),
        .library(name: "FileConversion", targets: ["FileConversion"]),
        .library(name: "TestSupport", targets: ["TestSupport"]),
        .library(name: "DeviceDrivers", targets: ["DeviceDrivers"]),
        .library(name: "HIDTransport", targets: ["HIDTransport"]),
        .library(name: "BluetoothTransport", targets: ["BluetoothTransport"]),
        .library(name: "SupportPackage", targets: ["SupportPackage"]),
    ],
    dependencies: [
        // Own repositories since change split-repositories; 0.x minor releases may break, so only 0.1.x.
        .package(url: "https://github.com/mytracks/GPSLoggerKit.git", .upToNextMinor(from: "0.1.0")),
        .package(url: "https://github.com/mytracks/GPSLoggerKitGPL.git", .upToNextMinor(from: "0.1.0")),
    ],
    targets: [
        .target(
            name: "LoggerCore",
            dependencies: [.product(name: "GPSLoggerKit", package: "GPSLoggerKit")],
            resources: [.process("Resources")]
        ),
        .target(name: "SerialTransport", dependencies: ["LoggerCore"]),
        .target(name: "GPXExport", dependencies: ["LoggerCore", .product(name: "GPSLoggerKit", package: "GPSLoggerKit")]),
        .target(name: "DiagnosticCapture", dependencies: ["LoggerCore"]),
        .target(
            name: "FileConversion",
            dependencies: [
                .product(name: "GPSLoggerKit", package: "GPSLoggerKit"),
                .product(name: "GPSLoggerKitGPL", package: "GPSLoggerKitGPL"),
            ]
        ),
        .target(
            name: "DeviceDrivers",
            dependencies: [
                "LoggerCore", "SerialTransport", "DiagnosticCapture",
                .product(name: "GPSLoggerKit", package: "GPSLoggerKit"),
                .product(name: "GPSLoggerKitGPL", package: "GPSLoggerKitGPL"),
            ]
        ),
        .target(
            name: "HIDTransport",
            dependencies: [
                "DeviceDrivers", "LoggerCore",
                .product(name: "GPSLoggerKit", package: "GPSLoggerKit"),
                .product(name: "GPSLoggerKitGPL", package: "GPSLoggerKitGPL"),
            ]
        ),
        .target(name: "BluetoothTransport", dependencies: ["DeviceDrivers", "LoggerCore"]),
        .target(name: "SupportPackage", dependencies: ["LoggerCore", "SerialTransport", "DiagnosticCapture"]),
        .target(
            name: "TestSupport",
            dependencies: ["LoggerCore", "DiagnosticCapture", .product(name: "GPSLoggerKit", package: "GPSLoggerKit")]
        ),

        .testTarget(
            name: "LoggerCoreTests",
            dependencies: ["LoggerCore", "TestSupport", .product(name: "GPSLoggerKit", package: "GPSLoggerKit")]
        ),
        .testTarget(name: "SerialTransportTests", dependencies: ["SerialTransport", "LoggerCore"]),
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
        .testTarget(
            name: "DeviceDriversTests",
            dependencies: [
                "DeviceDrivers", "LoggerCore", "SerialTransport", "TestSupport", "DiagnosticCapture",
                .product(name: "GPSLoggerKit", package: "GPSLoggerKit"),
                .product(name: "GPSLoggerKitGPL", package: "GPSLoggerKitGPL"),
            ]
        ),
        .testTarget(name: "HIDTransportTests", dependencies: ["HIDTransport", "DeviceDrivers", "LoggerCore"]),
        .testTarget(name: "BluetoothTransportTests", dependencies: ["BluetoothTransport", "DeviceDrivers", "LoggerCore"]),
        .testTarget(name: "SupportPackageTests", dependencies: ["SupportPackage", "SerialTransport", "DiagnosticCapture", "LoggerCore"]),
        .testTarget(
            name: "FileConversionTests",
            dependencies: ["FileConversion", .product(name: "GPSLoggerKit", package: "GPSLoggerKit")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
