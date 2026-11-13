// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import GPSLoggerKit
@testable import GPSLoggerKitGPL

private let fixturesDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

private func fixture(_ name: String) throws -> FileInput {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try FileInput.load(url)
}

private func date(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

/// The expected values are those of the gpsbabel 1.7.0 binary for the same file (black box, design D7);
/// deviations (design D4) are noted.
@Suite("Fixture of SkyTraq dumps")
struct SkyTraqFixtureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GPSLOGGERKITGPL_WRITE_FIXTURES"] == "1"))
    func writeFixture() throws {
        try SkyTraqTestDump.venus().data.write(to: fixturesDirectory.appendingPathComponent("venus.bin"))
    }

    @Test func fixtureMatchesTheEncoder() throws {
        #expect(try fixture("venus.bin").data == SkyTraqTestDump.venus().data)
    }

    /// Read through the app's catalog (GPSLoggerKit plus this package).
    @Test func venusDump() throws {
        let input = try fixture("venus.bin")
        let catalog = FormatCatalog.standard.adding(GPLFileFormats.all)
        let format = try #require(catalog.detect(prefix: input.data.prefix(4096), fileName: input.name))
        #expect(format.id == .skytraqBin)
        let result = try FileFormats.readSynchronously([input], format: SkyTraqBinFileFormat(reference: skyTraqReference),
                                                       options: ImportOptions(referenceDate: skyTraqReference))
        #expect(result.recording.tracks.map(\.name) == ["venus"])
        let points = try #require(result.recording.tracks.first?.segments.first?.points)
        #expect(points.count == 516)
        #expect(points.first?.time == date("2026-07-22T11:59:42Z"))
        #expect(points[508].time == date("2026-07-22T12:08:10Z"))
        #expect(points[509].time == date("2026-07-22T12:09:42Z"))
        #expect(abs(points[509].latitude - 50.01) < 1e-5 && abs(points[509].longitude - 8.02) < 1e-5)
        #expect(abs((points[509].elevation ?? 0) - 150.5) < 0.6)
        #expect(points[509].quality.speed == 10)
        // Multi-Hz items keep their milliseconds (gpsbabel truncates them to seconds).
        #expect(points[513].time == date("2026-07-22T12:10:02Z"))
        #expect(points[514].time.map { $0.timeIntervalSince(points[513].time!) }.map { abs($0 - 0.1) < 0.0005 } == true)
        #expect(points.last?.elevation == 160.75)
        #expect(result.recording.waypoints.map(\.name) == ["POI 1", "POI 2"])
        #expect(result.warnings.isEmpty)
    }

    #if os(macOS)
    @Test func gpxIsWellFormed() throws {
        let input = try fixture("venus.bin")
        let result = try FileFormats.readSynchronously([input], format: SkyTraqBinFileFormat(reference: skyTraqReference))
        let gpx = GPXWriter(creator: "GPSLoggerKitGPL tests").data(for: result.recording, createdAt: Date())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("skytraq-\(UUID().uuidString).gpx")
        try gpx.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try XMLDocument(contentsOf: url, options: [])
        #expect(document.rootElement()?.name == "gpx")
    }
    #endif
}

/// Writes the GPX of the fixture for the manual black-box comparison with gpsbabel (task 3.2).
@Test(.enabled(if: ProcessInfo.processInfo.environment["GPSLOGGERKITGPL_COMPARE_OUT"] != nil))
func writeComparisonGPX() throws {
    let path = try #require(ProcessInfo.processInfo.environment["GPSLOGGERKITGPL_COMPARE_OUT"])
    let input = try FileInput.load(fixturesDirectory.appendingPathComponent("venus.bin"))
    let result = try FileFormats.readSynchronously([input], format: SkyTraqBinFileFormat(reference: skyTraqReference))
    try GPXWriter(creator: "compare").data(for: result.recording, createdAt: Date()).write(to: URL(fileURLWithPath: path))
}
