import FileConversion
import Foundation
import GPSLoggerKit
import Testing

/// Stands in for a format of GPSLoggerKitGPL: files starting with `TESTFORMAT`, one waypoint per file.
private struct ExtraFormat: FileFormat {
    var id: FileFormatID { "extra-test" }
    var displayName: String { "Extra" }
    var fileExtensions: [String] { ["xtr"] }

    func matches(prefix: Data) -> Bool {
        prefix.starts(with: Data("TESTFORMAT".utf8))
    }

    func read(_ inputs: [FileInput]) throws -> ImportResult {
        ImportResult(recording: Recording(waypoints: inputs.map { Waypoint(latitude: 50, longitude: 8, name: $0.name) }))
    }
}

@Suite("App formats")
struct AppFormatsTests {
    @Test func appCatalogStartsWithGPSLoggerKit() {
        #expect(Array(AppFormats.catalog.all.map(\.id).prefix(FileFormats.all.count)) == FileFormats.all.map(\.id))
    }

    /// Spec `file-conversion`, "Format from the GPL package".
    @Test func formatOfAnAddedPackageIsConverted() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppFormatsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let extra = directory.appendingPathComponent("marke.xtr")
        try Data("TESTFORMAT\n".utf8).write(to: extra)
        let nmea = directory.appendingPathComponent("a.nmea")
        let sentences = (0..<5).map { i -> String in
            let body = "GPRMC,12000\(i),A,5144.4694,N,00840.8580,E,10.0,90.0,021126,,,A"
            return "$" + body + "*" + String(format: "%02X", body.utf8.reduce(UInt8(0)) { $0 ^ $1 })
        }
        try Data((sentences.joined(separator: "\n") + "\n").utf8).write(to: nmea)

        let catalog = AppFormats.catalog.adding([ExtraFormat()])
        let plan = try FileConverter.plan(for: [nmea, extra], catalog: catalog)
        #expect(plan.groups.map(\.formatID) == [.nmea, "extra-test"])
        #expect(plan.unrecognized.isEmpty)
        let result = try await FileConverter.convert(plan, catalog: catalog)
        #expect(result.recording.tracks.count == 1)
        #expect(result.recording.waypoints.map(\.name) == ["marke.xtr"])

        // Without the extra format the file is not recognized.
        #expect(try FileConverter.plan(for: [nmea, extra]).unrecognized == ["marke.xtr"])
    }
}

@Suite("License copies")
struct LicenseCopyTests {
    private static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// The checkout of a package dependency: `.build/checkouts` of `swift test` or `SourcePackages/checkouts` of the
    /// app build in `build/DerivedData`.
    private static func checkout(_ name: String) throws -> URL {
        let candidates = [
            repository.appendingPathComponent("Packages/GPSLoaderKit/.build/checkouts/\(name)"),
            repository.appendingPathComponent("build/DerivedData/SourcePackages/checkouts/\(name)"),
        ]
        return try #require(candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("LICENSE").path) },
                            "no checkout of \(name)")
    }

    /// The copy bundled with the app (`Vendor/Licenses`) matches the license of GPSLoggerKit (design D5).
    @Test(.enabled(if: FileManager.default.fileExists(atPath: repository.appendingPathComponent("Vendor").path)))
    func mitLicenseCopyMatchesGPSLoggerKit() throws {
        let copy = try Data(contentsOf: Self.repository.appendingPathComponent("Vendor/Licenses/MIT-GPSLoggerKit.txt"))
        let original = try Data(contentsOf: Self.checkout("GPSLoggerKit").appendingPathComponent("LICENSE"))
        #expect(copy == original)
    }

    /// The repository and GPSLoggerKitGPL carry the same GPL-3.0 text as the bundled one (`Vendor/Licenses`).
    @Test(.enabled(if: FileManager.default.fileExists(atPath: repository.appendingPathComponent("Vendor").path)))
    func gplLicenseFilesMatch() throws {
        let bundled = try Data(contentsOf: Self.repository.appendingPathComponent("Vendor/Licenses/GPL-3.0.txt"))
        #expect(try Data(contentsOf: Self.repository.appendingPathComponent("LICENSE")) == bundled)
        #expect(try Data(contentsOf: Self.checkout("GPSLoggerKitGPL").appendingPathComponent("LICENSE")) == bundled)
    }
}
