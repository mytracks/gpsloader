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

private func readDetected(_ name: String, as id: FileFormatID) throws -> ImportResult {
    let input = try fixture(name)
    let catalog = FormatCatalog.standard.adding(GPLFileFormats.all)
    let format = try #require(catalog.detect(prefix: input.data.prefix(4096), fileName: name))
    #expect(format.id == id)
    return try FileFormats.readSynchronously([input], format: format, options: ImportOptions(referenceDate: skyTraqReference))
}

/// Expected values agree with the gpsbabel 1.7.0 binary for the same files (black box, design D7).
@Suite("Fixtures of MTK dumps")
struct MTKFixtureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GPSLOGGERKITGPL_WRITE_FIXTURES"] == "1"))
    func writeFixtures() throws {
        try MTKTestDump.mtkFixture().data.write(to: fixturesDirectory.appendingPathComponent("mtk.bin"))
        try MTKTestDump.m241Fixture().data.write(to: fixturesDirectory.appendingPathComponent("m241.bin"))
    }

    @Test func fixturesMatchTheEncoder() throws {
        #expect(try fixture("mtk.bin").data == MTKTestDump.mtkFixture().data)
        #expect(try fixture("m241.bin").data == MTKTestDump.m241Fixture().data)
    }

    @Test func mtkFixture() throws {
        let result = try readDetected("mtk.bin", as: .mtkBin)
        #expect(result.recording.tracks.map(\.name) == ["mtk (1)", "mtk (2)"])
        #expect(result.recording.tracks.map(\.pointCount) == [4, 3])
        let first = try #require(result.recording.tracks.first?.segments.first?.points)
        #expect(first[1].time == Date(timeIntervalSince1970: TimeInterval(MTKTestDump.start) + 1.25))
        #expect(first[3].latitude == 50.0003 && first[3].longitude == 8.0006 && first[3].elevation == 103)
        #expect(first[0].quality.course == 90 && first[0].quality.satellites == 7 && first[0].quality.hdop == 1)
        #expect(result.recording.waypoints.map(\.name) == ["POI 1"])
        #expect(result.recording.waypoints.first?.latitude == 50.0002)
        #expect(result.warnings.isEmpty)
    }

    @Test func m241Fixture() throws {
        let result = try readDetected("m241.bin", as: .m241Bin)
        #expect(result.recording.tracks.map(\.name) == ["m241"])
        #expect(result.recording.trackPointCount == 4)
        #expect(result.recording.waypoints.count == 1)
        #expect(result.warnings.isEmpty)
    }

    /// Writes the GPX of the fixtures for the black-box comparison with gpsbabel (task 3.2).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GPSLOGGERKITGPL_COMPARE_DIR"] != nil),
          arguments: ["mtk.bin", "m241.bin"])
    func writeComparisonGPX(name: String) throws {
        let directory = try #require(ProcessInfo.processInfo.environment["GPSLOGGERKITGPL_COMPARE_DIR"])
        let input = try fixture(name)
        let format: any FileFormat = name == "mtk.bin" ? MTKBinFileFormat() : M241BinFileFormat()
        let result = try FileFormats.readSynchronously([input], format: format)
        try GPXWriter(creator: "compare").data(for: result.recording, createdAt: Date())
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".gpx"))
    }
}
