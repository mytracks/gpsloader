// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import GPSLoggerKit
@testable import GPSLoggerKitGPL

/// Builds synthetic Alan Map500 `.trl` files (no real location data).
enum AlanTestFile {
    struct Point {
        var x: Int32, y: Int32, height: Int16, speed: Int16
    }

    struct TrackHeader {
        var slot: Int
        var name: String
        var totalPoints: Int16
        var points: [Point]
    }

    static func make(_ tracks: [TrackHeader], id: UInt32 = AlanFileFormat.headerID) -> Data {
        var bytes = [UInt8](repeating: 0, count: AlanFileFormat.minimumLength)
        func put<T: FixedWidthInteger>(_ value: T, at offset: Int) {
            withUnsafeBytes(of: value.littleEndian) { bytes.replaceSubrange(offset..<(offset + $0.count), with: $0) }
        }
        put(id, at: AlanFileFormat.headerOffset)
        put(Int16(tracks.count), at: AlanFileFormat.headerOffset + 4)
        for track in tracks {
            let header = AlanFileFormat.headerOffset + 16 + track.slot * AlanFileFormat.trackHeaderLength
            put(track.totalPoints, at: header)
            let name = Array(track.name.utf8.prefix(12)) + [UInt8](repeating: 0x20, count: max(0, 12 - track.name.utf8.count))
            bytes.replaceSubrange((header + 4)..<(header + 16), with: name)
            put(UInt32(1), at: header + 32)  // occupied
            put(UInt32(1), at: header + 36)  // show
            let log = AlanFileFormat.trackLogOffset(track.slot)
            for (j, p) in track.points.enumerated() {
                put(p.x, at: log + 8 * j)
                put(p.y, at: log + 8 * j + 4)
                put(p.speed, at: log + AlanFileFormat.maxPoints * 8 + 4 * j)
                put(p.height, at: log + AlanFileFormat.maxPoints * 8 + 4 * j + 2)
            }
        }
        return Data(bytes)
    }

    /// Degrees to Map500 units (degree · 36000); latitude is stored negated.
    static func point(latitude: Double, longitude: Double, meters: Double, metersPerSecond: Double) -> Point {
        Point(x: Int32((longitude * 36000).rounded()), y: Int32((-latitude * 36000).rounded()),
              height: Int16((meters * 5).rounded()), speed: Int16((metersPerSecond * 720).rounded()))
    }

    static func line(_ count: Int, latitude: Double, longitude: Double) -> [Point] {
        (0..<count).map { k in
            point(latitude: latitude + Double(k) / 36000, longitude: longitude - Double(k) / 36000,
                  meters: 100 + Double(k % 40) * 0.2, metersPerSecond: Double(k % 30) * 0.5)
        }
    }

    /// `map500.trl`: two tracks, one in the south and one in the west.
    static func fixture() -> Data {
        make([TrackHeader(slot: 1, name: "SOUTH", totalPoints: 120, points: line(120, latitude: -33.5, longitude: 151.25)),
              TrackHeader(slot: 6, name: "WEST TRACK", totalPoints: 80, points: line(80, latitude: 50.5, longitude: -8.25))])
    }
}

@Suite("Alan Map500 track logs")
struct AlanTests {
    private func read(_ data: Data, name: String = "map500.trl") throws -> ImportResult {
        try AlanFileFormat().read([FileInput(name: name, data: data)])
    }

    /// Scenario "Falsche Kennung".
    @Test func wrongID() {
        #expect(throws: GPSLoggerError.self) { try read(AlanTestFile.make([], id: 0x1234_5678)) }
    }

    /// Scenario "Zu kurze Datei".
    @Test func tooShort() {
        #expect(throws: GPSLoggerError.self) { try read(AlanTestFile.make([]).prefix(AlanFileFormat.minimumLength - 1)) }
    }

    /// Scenario "Zwei belegte Tracks".
    @Test func twoTracks() throws {
        let data = AlanTestFile.make([
            .init(slot: 0, name: "FIRST", totalPoints: 100, points: AlanTestFile.line(100, latitude: 10, longitude: 20)),
            .init(slot: 3, name: "SECOND", totalPoints: 2500, points: AlanTestFile.line(2500, latitude: 11, longitude: 21)),
        ])
        let result = try read(data)
        #expect(result.recording.tracks.map(\.name) == ["FIRST", "SECOND"])
        #expect(result.recording.tracks.map(\.pointCount) == [100, 2500])
        #expect(result.warnings.isEmpty)
        let last = try #require(result.recording.tracks.last?.segments.first?.points.last)
        #expect(abs(last.latitude - (11 + 2499.0 / 36000)) < 1e-9)
    }

    /// Scenario "Umrechnung".
    @Test func conversion() throws {
        let point = AlanTestFile.Point(x: 288_000, y: -1_800_000, height: 500, speed: 7200)
        let result = try read(AlanTestFile.make([.init(slot: 2, name: "", totalPoints: 1, points: [point])]), name: "Tour.trl")
        let p = try #require(result.recording.tracks.first?.segments.first?.points.first)
        #expect(p.latitude == 50 && p.longitude == 8 && p.elevation == 100 && p.quality.speed == 10 && p.time == nil)
        #expect(result.recording.tracks.first?.name == "Tour")  // no name in the header
        let negative = AlanTestFile.Point(x: 0, y: 0, height: 0, speed: -1)
        let unknown = try read(AlanTestFile.make([.init(slot: 0, name: "N", totalPoints: 1, points: [negative])]))
        #expect(unknown.recording.tracks.first?.segments.first?.points.first?.quality.speed == nil)
    }

    /// Scenario "Zu große Punktzahl".
    @Test func tooManyPoints() throws {
        let result = try read(AlanTestFile.make([.init(slot: 7, name: "BIG", totalPoints: 3000,
                                                       points: AlanTestFile.line(2500, latitude: 1, longitude: 1))]))
        #expect(result.recording.trackPointCount == 2500)
        #expect(result.warnings.map(\.kind) == [.malformedRecord])
    }

    /// Scenario "Textdatei mit Endung trl" and detection of a real layout.
    @Test func detection() {
        let format = AlanFileFormat()
        let text = Data(String(repeating: "Track,1,2,3\n", count: 400).utf8)
        #expect(!format.matches(prefix: text.prefix(4096)))
        #expect(format.matches(prefix: AlanTestFile.fixture().prefix(4096)))
        #expect(!format.matches(prefix: AlanTestFile.fixture().prefix(100)))
        let catalog = FormatCatalog.standard.adding(GPLFileFormats.all)
        #expect(catalog.detect(prefix: AlanTestFile.fixture().prefix(4096), fileName: "map500.trl")?.id == .alanTrl)
        #expect(catalog.detect(prefix: text.prefix(4096), fileName: "x.trl")?.id != .alanTrl)
    }

    /// Spec `logger-kit-gpl`, "Alan-Format abfragen".
    @Test func alanIsInTheCatalog() throws {
        #expect(GPLFileFormats.all.last?.id == .alanTrl)
        #expect(GPLFileFormats.all.last?.fileExtensions == ["trl"])
        let credit = try #require(GPLFileFormats.credits.first { $0.project == "GPSBabel" })
        #expect(credit.authors.contains("Gunar Megger"))
        #expect(L10n.string("format.alantrl", localization: "de") != "format.alantrl")
    }
}

// MARK: - Fixture

private let fixturesDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
private let fixtureName = "map500.trl"

@Suite("Fixture of Alan Map500 track logs")
struct AlanFixtureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GPSLOGGERKITGPL_WRITE_FIXTURES"] == "1"))
    func writeFixture() throws {
        try AlanTestFile.fixture().write(to: fixturesDirectory.appendingPathComponent(fixtureName))
    }

    @Test func fixtureIsReadThroughTheCatalog() throws {
        let url = try #require(Bundle.module.url(forResource: fixtureName, withExtension: nil, subdirectory: "Fixtures"))
        let input = try FileInput.load(url)
        #expect(input.data == AlanTestFile.fixture())
        let catalog = FormatCatalog.standard.adding(GPLFileFormats.all)
        let format = try #require(catalog.detect(prefix: input.data.prefix(4096), fileName: fixtureName))
        #expect(format.id == .alanTrl)
        let result = try FileFormats.readSynchronously([input], format: format)
        #expect(result.recording.tracks.map(\.name) == ["SOUTH", "WEST TRACK"])
        #expect(result.recording.tracks.map(\.pointCount) == [120, 80])
    }

    /// Writes the GPX of the fixture for the black-box comparison with gpsbabel (task 3.1).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GPSLOGGERKITGPL_COMPARE_DIR"] != nil))
    func writeComparisonGPX() throws {
        let directory = try #require(ProcessInfo.processInfo.environment["GPSLOGGERKITGPL_COMPARE_DIR"])
        let result = try AlanFileFormat().read([FileInput(name: fixtureName, data: AlanTestFile.fixture())])
        try GPXWriter(creator: "compare").data(for: result.recording, createdAt: Date())
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent(fixtureName + ".gpx"))
    }
}
