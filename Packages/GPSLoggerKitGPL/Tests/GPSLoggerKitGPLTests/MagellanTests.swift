// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import GPSLoggerKit
@testable import GPSLoggerKitGPL

/// Builds synthetic Magellan sentences and files (no real location data).
enum MagellanTestFile {
    static func sentence(_ body: String, checksum: UInt8? = nil) -> String {
        let sum = checksum ?? body.utf8.reduce(0, ^)
        return "$\(body)*\(String(format: "%02X", sum))\r\n"
    }

    /// `ddmm.mmm` / `dddmm.mmm` with hemisphere.
    static func coordinate(_ degrees: Double, width: Int, positive: String, negative: String) -> String {
        let value = abs(degrees)
        let whole = Int(value)
        let minutes = (value - Double(whole)) * 60
        return String(format: "%0\(width)d%06.3f", whole, minutes) + "," + (degrees < 0 ? negative : positive)
    }

    static func track(latitude: Double, longitude: Double, altitude: Int, time: Date) -> String {
        let c = Calendar.utc.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: time)
        let hundredths = Int((Double(c.nanosecond!) / 1e7).rounded())
        let clock = String(format: "%02d%02d%02d.%02d", c.hour!, c.minute!, c.second!, hundredths)
        let date = String(format: "%02d%02d%02d", c.day!, c.month!, c.year! % 100)
        return sentence("PMGNTRK,\(coordinate(latitude, width: 2, positive: "N", negative: "S")),"
                        + "\(coordinate(longitude, width: 3, positive: "E", negative: "W")),"
                        + String(format: "%05d", altitude) + ",M,\(clock),A,,\(date)")
    }

    static func waypoint(latitude: Double, longitude: Double, altitude: Int, name: String, comment: String,
                         icon: String = "a") -> String {
        sentence("PMGNWPL,\(coordinate(latitude, width: 2, positive: "N", negative: "S")),"
                 + "\(coordinate(longitude, width: 3, positive: "E", negative: "W")),"
                 + String(format: "%07d", altitude) + ",M,\(name),\(comment),\(icon)")
    }

    static let start = Date(timeIntervalSince1970: 1_793_620_800.5)  // 2026-11-02T12:00:00.5Z

    /// `track01.log`: 50 track points (west, crossing the equator) and two waypoint sentences.
    static func trackLog() -> String {
        var text = ""
        for k in 0..<50 {
            text += track(latitude: 0.0025 - Double(k) * 0.0001, longitude: -8.25 - Double(k) * 0.0002,
                          altitude: 100 + k, time: start.addingTimeInterval(Double(k)))
            if k == 10 || k == 30 {
                text += waypoint(latitude: 1, longitude: -8, altitude: 0, name: "IGNORED\(k)", comment: "in a log")
            }
        }
        return text
    }

    /// `poi.upt`: three waypoints, one with an escaped comma in the comment.
    static func waypointFile() -> String {
        waypoint(latitude: 50.5, longitude: -8.25, altitude: 257, name: "HOME", comment: "A\u{1B}2CB", icon: "c")
            + waypoint(latitude: -33.25, longitude: 151.5, altitude: 12, name: "SOUTH", comment: "")
            + waypoint(latitude: 10, longitude: 20, altitude: 0, name: "P3", comment: "Third")
    }
}

extension Calendar {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}

private func input(_ name: String, _ text: String) -> FileInput {
    FileInput(name: name, data: Data(text.utf8))
}

@Suite("Magellan sentences and files")
struct MagellanTests {
    /// Scenario "Tracksatz".
    @Test func trackSentence() throws {
        let text = MagellanTestFile.sentence("PMGNTRK,5030.000,N,00815.000,W,00100,M,123456.50,A,,021126")
        #expect(text.hasSuffix("*6D\r\n"))
        let sentence = try #require(MagellanSentences.parse(text))
        #expect(sentence.checksumIsValid)
        let point = MagellanSentences.trackPoint(sentence.text)
        #expect(abs(point.latitude - 50.5) < 1e-9 && abs(point.longitude + 8.25) < 1e-9)
        #expect(point.elevation == 100)
        #expect(point.time == ISO8601DateFormatter().date(from: "2026-11-02T12:34:56Z").map { $0.addingTimeInterval(0.5) })
    }

    /// Scenario "Wegpunkt mit Komma im Kommentar".
    @Test func waypointWithEscapedComma() throws {
        let text = MagellanTestFile.waypoint(latitude: 50.5, longitude: -8.25, altitude: 257, name: "HOME",
                                             comment: "A\u{1B}2CB", icon: "c")
        let waypoint = MagellanSentences.waypoint(try #require(MagellanSentences.parse(text)).text)
        #expect(waypoint.name == "HOME" && waypoint.comment == "A,B" && waypoint.elevation == 257)
        #expect(abs(waypoint.latitude - 50.5) < 1e-9 && abs(waypoint.longitude + 8.25) < 1e-9)
    }

    @Test func dequoteEdgeCases() {
        #expect(MagellanSentences.dequote("a\u{1B}FFFFFFb") == "ab")  // corrupted data
        #expect(MagellanSentences.dequote("a\u{1B}07b") == "a$b")  // not printable
        #expect(MagellanSentences.dequote("ab\u{1B}2") == "ab")  // truncated escape
        #expect(MagellanSentences.dequote("a\u{1B}zzb") == "azzb")  // not hex: the source loops forever
    }

    @Test func shortAndForeignLines() {
        #expect(MagellanSentences.parse("$A*0") == nil)
        #expect(MagellanSentences.parse("GA,1*00") == nil)
        #expect(MagellanSentences.parse("$PMGNCMD,END*3D\r")?.checksumIsValid == true)
    }

    /// Scenario "Tracklog-Datei".
    @Test func trackLogFile() throws {
        let result = try MagellanFileFormat().read([input("TRACK01.LOG", MagellanTestFile.trackLog())])
        #expect(result.recording.tracks.map(\.name) == ["TRACK01"])
        #expect(result.recording.trackPointCount == 50)
        #expect(result.recording.waypoints.isEmpty)
        #expect(result.warnings.isEmpty)
        let points = try #require(result.recording.tracks.first?.segments.first?.points)
        #expect(points[49].latitude < 0 && points[49].longitude < -8.25)
        #expect(points[1].time == MagellanTestFile.start.addingTimeInterval(1))
    }

    /// Scenario "Wegpunktdatei".
    @Test func waypointFile() throws {
        let result = try MagellanFileFormat().read([input("POI.UPT", MagellanTestFile.waypointFile())])
        #expect(result.recording.waypoints.map(\.name) == ["HOME", "SOUTH", "P3"])
        #expect(abs(result.recording.waypoints[1].latitude + 33.25) < 1e-9 && abs(result.recording.waypoints[1].longitude - 151.5) < 1e-9)
        #expect(result.recording.tracks.isEmpty)
    }

    /// Scenario "Falsche Prüfsumme", plus a line without `$` and the end command.
    @Test func checksumMismatchAndForeignLines() throws {
        let start = MagellanTestFile.start
        let text = MagellanTestFile.track(latitude: 1, longitude: 2, altitude: 3, time: start)
            + MagellanTestFile.sentence("PMGNTRK,0100.000,N,00200.000,E,00003,M,120001.50,A,,021126", checksum: 0x00)
            + "\r\ngarbage\r\n"
            + MagellanTestFile.sentence("PMGNCMD,END")
            + MagellanTestFile.track(latitude: 1, longitude: 2, altitude: 3, time: start)
        let result = try MagellanFileFormat().read([input("t.log", text)])
        #expect(result.recording.trackPointCount == 2)
        #expect(result.warnings.map(\.kind) == [.checksumMismatch, .malformedRecord])
        #expect(result.warnings.map(\.firstLine) == [2, 4])
    }

    /// Scenario "NMEA-Datei" and detection of the Magellan files.
    @Test func detection() {
        let format = MagellanFileFormat()
        let nmea = "$GPRMC,120000,A,5030.000,N,00815.000,E,0.0,0.0,021126,,*12\r\n$GPGGA,120000,5030.000,N,00815.000,E,1,05,1.0,100.0,M,,,,*1D\r\n"
            + "$GPGSA,A,3,01,02,03,,,,,,,,,,2.0,1.0,1.5*35\r\n"
        #expect(!format.matches(prefix: Data(nmea.utf8)))
        #expect(format.matches(prefix: Data(MagellanTestFile.trackLog().utf8)))
        #expect(format.matches(prefix: Data(MagellanTestFile.waypointFile().utf8)))
        let catalog = FormatCatalog.standard.adding(GPLFileFormats.all)
        #expect(catalog.detect(prefix: Data(MagellanTestFile.trackLog().utf8), fileName: "TRACK01.LOG")?.id == .magellan)
        #expect(catalog.detect(prefix: Data(nmea.utf8), fileName: "x.log")?.id == .nmea)
    }

    /// Spec `logger-kit-gpl`, "Magellan-Format abfragen".
    @Test func magellanIsInTheCatalog() throws {
        let format = try #require(GPLFileFormats.all.first { $0.id == .magellan })
        #expect(format.fileExtensions == ["log", "upt", "rte"])
        #expect(L10n.string("format.magellan", localization: "de") != "format.magellan")
    }
}

// MARK: - Fixtures

private let fixturesDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
private let fixtureFiles: [(name: String, text: @Sendable () -> String)] = [
    ("track01.log", MagellanTestFile.trackLog), ("poi.upt", MagellanTestFile.waypointFile),
]

@Suite("Fixtures of Magellan files")
struct MagellanFixtureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GPSLOGGERKITGPL_WRITE_FIXTURES"] == "1"))
    func writeFixtures() throws {
        for file in fixtureFiles {
            try Data(file.text().utf8).write(to: fixturesDirectory.appendingPathComponent(file.name))
        }
    }

    @Test func fixturesAreReadThroughTheCatalog() throws {
        let catalog = FormatCatalog.standard.adding(GPLFileFormats.all)
        for file in fixtureFiles {
            let url = try #require(Bundle.module.url(forResource: file.name, withExtension: nil, subdirectory: "Fixtures"))
            let input = try FileInput.load(url)
            #expect(input.data == Data(file.text().utf8))
            let format = try #require(catalog.detect(prefix: input.data.prefix(4096), fileName: file.name))
            #expect(format.id == .magellan)
            let result = try FileFormats.readSynchronously([input], format: format)
            #expect(result.warnings.isEmpty)
        }
    }

    /// Writes the GPX of the fixtures for the black-box comparison with gpsbabel (task 3.1).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GPSLOGGERKITGPL_COMPARE_DIR"] != nil))
    func writeComparisonGPX() throws {
        let directory = try #require(ProcessInfo.processInfo.environment["GPSLOGGERKITGPL_COMPARE_DIR"])
        for file in fixtureFiles {
            let result = try MagellanFileFormat().read([FileInput(name: file.name, data: Data(file.text().utf8))])
            try GPXWriter(creator: "compare").data(for: result.recording, createdAt: Date())
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent(file.name + ".gpx"))
        }
    }
}
