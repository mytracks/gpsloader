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

private let fixtures: [(String, [UInt8], FileFormatID)] = [
    ("wbt202.tes", WintecTestFile.tesFixture(), .wintecTES),
    ("wbt200.bin", WintecTestFile.binFixture(), .wbtBin),
    ("wbt201.tk1", WintecTestFile.tk1Fixture(), .wbtTK1),
]

/// Expected values agree with the gpsbabel 1.7.0 binary for the same files (black box, design D7).
@Suite("Fixtures of Wintec files")
struct WintecFixtureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GPSLOGGERKITGPL_WRITE_FIXTURES"] == "1"))
    func writeFixtures() throws {
        for (name, bytes, _) in fixtures {
            try Data(bytes).write(to: fixturesDirectory.appendingPathComponent(name))
        }
    }

    @Test func fixturesMatchTheEncoderAndAreDetected() throws {
        let catalog = FormatCatalog.standard.adding(GPLFileFormats.all)
        for (name, bytes, id) in fixtures {
            let input = try fixture(name)
            #expect(input.data == Data(bytes))
            let format = try #require(catalog.detect(prefix: input.data.prefix(4096), fileName: name))
            #expect(format.id == id)
            let result = try FileFormats.readSynchronously([input], format: format)
            #expect(result.warnings.isEmpty)
            #expect(result.recording.trackPointCount == 5)
        }
    }

    /// Writes the GPX of the fixtures for the black-box comparison with gpsbabel (task 3.2).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GPSLOGGERKITGPL_COMPARE_DIR"] != nil))
    func writeComparisonGPX() throws {
        let directory = try #require(ProcessInfo.processInfo.environment["GPSLOGGERKITGPL_COMPARE_DIR"])
        let catalog = FormatCatalog.standard.adding(GPLFileFormats.all)
        for (name, _, id) in fixtures {
            let input = try fixture(name)
            let result = try FileFormats.readSynchronously([input], format: try #require(catalog.format(withID: id)))
            try GPXWriter(creator: "compare").data(for: result.recording, createdAt: Date())
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".gpx"))
        }
    }
}
