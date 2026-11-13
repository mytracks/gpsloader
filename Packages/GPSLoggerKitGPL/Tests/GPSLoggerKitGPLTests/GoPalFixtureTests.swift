// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import GPSLoggerKit
@testable import GPSLoggerKitGPL

private let fixturesDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
private let name = "track20261102_080000.trk"

private func fixture() throws -> FileInput {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try FileInput.load(url)
}

/// Positions and altitudes agree with the gpsbabel 1.7.0 binary for the same file (black box, design D7).
@Suite("Fixture of GoPal tracks")
struct GoPalFixtureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GPSLOGGERKITGPL_WRITE_FIXTURES"] == "1"))
    func writeFixture() throws {
        try Data(GoPalTestFile.fixture().utf8).write(to: fixturesDirectory.appendingPathComponent(name))
    }

    @Test func fixtureIsReadThroughTheCatalog() throws {
        let input = try fixture()
        #expect(input.data == Data(GoPalTestFile.fixture().utf8))
        let catalog = FormatCatalog.standard.adding(GPLFileFormats.all)
        let format = try #require(catalog.detect(prefix: input.data.prefix(4096), fileName: name))
        #expect(format.id == .gopal)
        let result = try FileFormats.readSynchronously([input], format: format)
        let points = try #require(result.recording.tracks.first?.segments.first?.points)
        #expect(points.count == 5)  // the jump and the 0/0 line are dropped
        #expect(points.first?.time == ISO8601DateFormatter().date(from: "2026-11-02T08:00:00Z").map { $0.addingTimeInterval(0.25) })
        #expect(points.map(\.elevation) == [200.5, 201.5, 202.5, 204.5, 205.5])
        #expect(result.warnings.isEmpty)
    }

    /// Writes the GPX of the fixture for the black-box comparison with gpsbabel (task 3.2).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GPSLOGGERKITGPL_COMPARE_DIR"] != nil))
    func writeComparisonGPX() throws {
        let directory = try #require(ProcessInfo.processInfo.environment["GPSLOGGERKITGPL_COMPARE_DIR"])
        let result = try FileFormats.readSynchronously([try fixture()], format: GoPalFileFormat())
        try GPXWriter(creator: "compare").data(for: result.recording, createdAt: Date())
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".gpx"))
    }
}
