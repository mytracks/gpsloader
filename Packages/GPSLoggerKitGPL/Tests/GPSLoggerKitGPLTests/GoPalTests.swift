// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import GPSLoggerKit
@testable import GPSLoggerKitGPL

private func read(_ text: String, name: String = "track20261102_080000.trk") throws -> ImportResult {
    try FileFormats.readSynchronously([FileInput(name: name, data: Data(text.utf8))], format: GoPalFileFormat(),
                                      options: ImportOptions(referenceDate: skyTraqReference))
}

private func points(_ result: ImportResult) -> [TrackPoint] {
    result.recording.tracks.flatMap { $0.segments.flatMap(\.points) }
}

private func date(_ text: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)!
}

/// A 9-field line (old format) at about 50° N, 8° E.
private func line9(_ tick: Int, _ time: String, lon: Double = 8.0, lat: Double = 50.0, fix: Int = 2) -> String {
    "\(tick), \(time), \(lon), \(lat), 100.5, 18.0, \(fix), 1.5, 6"
}

/// Fixture `track20261102_080000.trk` (design D7): 12 fields, a jump, a 0/0 line and a line with other fields.
enum GoPalTestFile {
    static func fixture() -> String {
        var lines: [String] = []
        for k in 0..<6 {
            let lat = k == 3 ? 51.0 : 50.05 + Double(k) * 0.0001  // k == 3: jump of about 100 km
            lines.append("\(1_000_000 * k + 250_000), 0800\(String(format: "%02d", k)), 8.05, \(lat), \(200 + k).5, 7.2, 2, 1.2, 8, 20261102, 0, 90")
        }
        lines.insert("9000000, 080010, 0.0, 0.0, 0, 0, 0, 0, 0, 20261102, 0, 0", at: 2)
        lines.insert("this,is,not,a,gopal,line", at: 4)
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}

@Suite("GoPal tracks")
struct GoPalTests {
    /// Scenario "Zeile mit Datum".
    @Test func lineWithDate() throws {
        let result = try read("3801444, 080558, 8.0, 50.0, 295.28, 36.0, 2, 2.9, 3, 20261102, 0, 0\n", name: "x.trk")
        let p = try #require(points(result).first)
        #expect(p.latitude == 50 && p.longitude == 8 && p.elevation == 295.28)
        #expect(p.time == date("2026-11-02T08:05:58.801Z"))
        #expect(p.quality.speed == 10 && p.quality.fix == .twoD && p.quality.hdop == 2.9 && p.quality.satellites == 3)
        #expect(result.warnings.isEmpty)
    }

    /// Scenario "Datum im Dateinamen", also for `A_…` names.
    @Test(arguments: ["track20261102_093000.trk", "A_20261102_093000.trk"])
    func dateFromFileName(name: String) throws {
        let result = try read(line9(0, "083000") + "\n" + line9(1_000_000, "083001", lat: 50.00001) + "\n", name: name)
        #expect(points(result).map(\.time) == [date("2026-11-02T08:30:00Z"), date("2026-11-02T08:30:01Z")])
    }

    /// Scenario "Über Mitternacht".
    @Test func overMidnight() throws {
        let result = try read(line9(0, "235959") + "\n" + line9(2_000_000, "000001", lat: 50.00001) + "\n")
        #expect(points(result).map(\.time) == [date("2026-11-02T23:59:59Z"), date("2026-11-03T00:00:01Z")])
    }

    /// Scenario "Kein Datum".
    @Test func noDate() throws {
        let result = try read(line9(0, "083000") + "\n" + line9(1_000_000, "083001", lat: 50.00001) + "\n", name: "log.trk")
        #expect(points(result).count == 2)
        #expect(points(result).allSatisfy { $0.time == nil })
        #expect(result.warnings == [ImportWarning(kind: .missingDate, count: 2, fileName: "log.trk")])
    }

    /// Scenario "Sprung in den Daten" (also without a date, using the time of day).
    @Test func jumpIsDropped() throws {
        let text = [line9(0, "080000"), line9(1_000_000, "080001", lat: 50.9), line9(2_000_000, "080002", lat: 50.00002)]
            .joined(separator: "\n")
        for name in ["track20261102_080000.trk", "log.trk"] {
            let result = try read(text, name: name)
            #expect(points(result).map(\.latitude) == [50.0, 50.00002])
        }
    }

    @Test func zeroAndOutOfRangeAreDropped() throws {
        let text = [line9(0, "080000", lon: 0), line9(1, "080001", lat: 95), line9(2, "080002")].joined(separator: "\n")
        #expect(try points(read(text)).count == 1)
    }

    /// Scenario "Track statt Route".
    @Test func trackWithoutWaypoints() throws {
        let text = (0..<3).map { line9($0 * 1_000_000, "08000\($0)", lat: 50 + Double($0) * 0.00001) }.joined(separator: "\n")
        let result = try read(text, name: "track20261102_080000.trk")
        #expect(result.recording.tracks.map(\.name) == ["track20261102_080000"])
        #expect(result.recording.trackPointCount == 3)
        #expect(result.recording.waypoints.isEmpty)
    }

    @Test func otherLinesAreSkipped() throws {
        let text = "header line\n" + line9(0, "080000") + "\n1,2,3\n"
        let result = try read(text)
        #expect(points(result).count == 1)
        #expect(result.warnings.isEmpty)
    }

    @Test func stopsSoonAfterCancellation() async throws {
        let line = "3801444, 080558, 8.0, 50.0, 295.28, 36.0, 2, 2.9, 3, 20261102, 0, 0\n"
        let file = FileInput(name: "big.trk", data: Data(String(repeating: line, count: 800_000).utf8))
        #expect(file.data.count > 50_000_000)
        let task = Task { try await FileFormats.read([file], format: GoPalFileFormat()) }
        task.cancel()
        let begin = Date()
        let result = await task.result
        #expect(Date().timeIntervalSince(begin) < 1)
        #expect(throws: CancellationError.self) { try result.get() }
    }

    /// Spec `logger-kit-gpl`, "GoPal abfragen".
    @Test func catalog() throws {
        #expect(GPLFileFormats.all.contains { $0.id == .gopal && $0.fileExtensions == ["trk"] })
        #expect(try #require(GPLFileFormats.credits.first).authors.contains("Jürgen Neumann"))
    }
}

@Suite("GoPal detection")
struct GoPalDetectionTests {
    private let catalog = FormatCatalog.standard.adding(GPLFileFormats.all)

    /// Scenario "GoPal-Datei".
    @Test func detected() {
        #expect(catalog.detect(prefix: Data(GoPalTestFile.fixture().utf8), fileName: "a.trk")?.id == .gopal)
        #expect(catalog.detect(prefix: Data((line9(0, "080000") + "\n").utf8), fileName: "a.txt")?.id == .gopal)
    }

    /// Scenario "Andere CSV-Datei" and other text formats.
    @Test func otherTextFiles() {
        let samples = [
            "INDEX,TAG,DATE,TIME,LATITUDE N/S,LONGITUDE E/W,HEIGHT,SPEED,HEADING\r\n1,T,261102,120000,50.0N,008.0E,1,2,3\r\n",
            "INDEX,RCR,DATE,TIME,VALID,LATITUDE,N/S,LONGITUDE,E/W,HEIGHT,SPEED,HEADING\r\n1,T,2026/11/02,12:00:00,3d,50,N,8,E,1,2,3\r\n",
            "$GPRMC,120000,A,5000.000,N,00800.000,E,0.0,0.0,021126,,*15\r\n",
            "AXXX001\r\nHFDTE021126\r\n",
        ]
        for sample in samples {
            #expect(!GoPalFileFormat().matches(prefix: Data(sample.utf8)))
        }
        for format in GPLFileFormats.all where format.id != .gopal {
            #expect(!format.matches(prefix: Data(GoPalTestFile.fixture().utf8)), "\(format.id) matches a GoPal file")
        }
        for format in FileFormats.all {
            #expect(!format.matches(prefix: Data(GoPalTestFile.fixture().utf8)), "\(format.id) matches a GoPal file")
        }
    }
}
