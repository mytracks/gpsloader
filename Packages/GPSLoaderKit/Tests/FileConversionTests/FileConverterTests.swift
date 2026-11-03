import FileConversion
import Foundation
import GPSLoggerKit
import Testing

/// A sentence with a correct checksum.
private func nmea(_ body: String) -> String {
    let checksum = body.utf8.reduce(UInt8(0)) { $0 ^ $1 }
    return "$" + body + "*" + String(format: "%02X", checksum)
}

/// NMEA text with `count` RMC sentences, one per second from 12:00:00, on the given date (ddmmyy).
private func nmeaTrack(count: Int, date: String = "021126") -> String {
    (0..<count).map { i in
        let time = String(format: "12%02d%02d", i / 60, i % 60)
        return nmea("GPRMC,\(time),A,5144.4694,N,00840.8580,E,10.0,90.0,\(date),,,A")
    }.joined(separator: "\n") + "\n"
}

private let igcText = "AXXX001\nHFDTE020726\nB1101355206343N00006198WA0058700558\nB1101405206400N00006100WA0059000561\n"

private func gpx(_ body: String) -> String {
    "<?xml version=\"1.0\"?>\n<gpx version=\"1.1\" creator=\"t\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n\(body)\n</gpx>\n"
}

private func waypoints(_ count: Int) -> String {
    (0..<count).map { "<wpt lat=\"51.\($0)\" lon=\"8.\($0)\"><name>W\($0)</name></wpt>" }.joined(separator: "\n")
}

/// A temporary directory with files; removed when the value is released.
private final class TempFiles {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileConversionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func file(_ name: String, _ text: String) throws -> URL {
        try file(name, Data(text.utf8))
    }

    func file(_ name: String, _ data: Data) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
}

private func points(_ recording: Recording) -> [TrackPoint] {
    recording.tracks.flatMap(\.segments).flatMap(\.points)
}

@Suite("FileConverter – plan")
struct FileConverterPlanTests {
    /// Scenario "NMEA mit Endung .LOG".
    @Test func nmeaWithLogExtension() throws {
        let files = try TempFiles()
        let plan = try FileConverter.plan(for: [try files.file("GPS_20261102.LOG", nmeaTrack(count: 5))])
        #expect(plan.groups.map(\.formatID) == [.nmea])
        #expect(plan.unrecognized.isEmpty)
    }

    /// Scenario "Eine von drei Dateien unbekannt".
    @Test func oneOfThreeUnknown() throws {
        let files = try TempFiles()
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])
        let plan = try FileConverter.plan(for: [
            try files.file("a.nmea", nmeaTrack(count: 3)), try files.file("photo.jpg", jpeg),
            try files.file("b.nmea", nmeaTrack(count: 3)),
        ])
        #expect(plan.unrecognized == ["photo.jpg"])
        #expect(plan.groups.count == 1)
        #expect(plan.groups[0].inputs.map(\.name) == ["a.nmea", "b.nmea"])
        #expect(!plan.isEmpty)
        #expect(plan.excludingUnrecognized().unrecognized.isEmpty)
        #expect(plan.excludingUnrecognized().groups.count == 1)
    }

    /// Scenario "Nur unbekannte Dateien".
    @Test func onlyUnknownFiles() throws {
        let files = try TempFiles()
        let plan = try FileConverter.plan(for: [try files.file("doc.pdf", "%PDF-1.7\n%âãÏÓ\n")])
        #expect(plan.isEmpty)
        #expect(plan.unrecognized == ["doc.pdf"])
    }

    @Test func groupsInOrderOfFirstOccurrence() throws {
        let files = try TempFiles()
        let plan = try FileConverter.plan(for: [
            try files.file("1.igc", igcText), try files.file("2.gpx", gpx(waypoints(1))),
            try files.file("3.igc", igcText), try files.file("4.nmea", nmeaTrack(count: 3)),
        ])
        #expect(plan.groups.map(\.formatID) == [.igc, .gpx, .nmea])
        #expect(plan.groups[0].inputs.map(\.name) == ["1.igc", "3.igc"])
    }

    @Test func emptyFileIsAnError() throws {
        let files = try TempFiles()
        let url = try files.file("empty.nmea", "")
        #expect(throws: GPSLoggerError(.empty, fileName: "empty.nmea")) { try FileConverter.plan(for: [url]) }
    }

    @Test func missingFileIsUnreadable() throws {
        let files = try TempFiles()
        let url = files.directory.appendingPathComponent("missing.nmea")
        #expect { try FileConverter.plan(for: [url]) } throws: { error in
            (error as? GPSLoggerError)?.kind == .unreadable && (error as? GPSLoggerError)?.fileName == "missing.nmea"
        }
    }
}

@Suite("FileConverter – convert")
struct FileConverterConvertTests {
    private let reference = Date(timeIntervalSince1970: 1_793_664_000)  // 2026-11-03

    private func convert(_ urls: [URL]) async throws -> ImportResult {
        try await FileConverter.convert(try FileConverter.plan(for: urls), referenceDate: reference)
    }

    /// Scenario "Zwei NMEA-Dateien".
    @Test func twoNMEAFiles() async throws {
        let files = try TempFiles()
        let result = try await convert([try files.file("a.nmea", nmeaTrack(count: 100)),
                                        try files.file("b.nmea", nmeaTrack(count: 100, date: "031126"))])
        #expect(result.recording.tracks.count == 1)
        #expect(result.recording.tracks[0].segments.count == 2)
        #expect(points(result.recording).count == 200)
    }

    /// Scenario "Gemischte Formate".
    @Test func mixedFormats() async throws {
        let files = try TempFiles()
        let track = "<trk><name>From GPX</name><trkseg><trkpt lat=\"1\" lon=\"2\"/><trkpt lat=\"1.1\" lon=\"2.1\"/></trkseg></trk>"
        let result = try await convert([try files.file("a.gpx", gpx(track)), try files.file("b.igc", igcText)])
        #expect(result.recording.tracks.map(\.name) == ["From GPX", "b"])
    }

    /// Scenario "Nur Wegpunkte".
    @Test func onlyWaypoints() async throws {
        let files = try TempFiles()
        let result = try await convert([try files.file("w.gpx", gpx(waypoints(12)))])
        #expect(result.recording.tracks.count == 1)
        #expect(points(result.recording).count == 12)
        #expect(result.recording.waypoints.count == 12)
    }

    @Test func waypointsNextToATrackStayWaypoints() async throws {
        let files = try TempFiles()
        let result = try await convert([try files.file("w.gpx", gpx(waypoints(3))), try files.file("f.igc", igcText)])
        #expect(result.recording.tracks.map(\.name) == ["f"])
        #expect(result.recording.waypoints.count == 3)
    }

    /// Scenario "Alter Logger mit Wochenüberlauf".
    @Test func weekRolloverIsCorrected() async throws {
        let files = try TempFiles()
        let result = try await convert([try files.file("old.nmea", nmeaTrack(count: 3, date: "150307"))])
        let expected = UTCComponents.date(2026, 10, 29, 12, 0, 0)
        #expect(points(result.recording).first?.time == expected)
    }

    /// Scenario "Name vorschlagen".
    @Test func suggestedName() {
        let urls = [URL(fileURLWithPath: "/tmp/flug1.igc"), URL(fileURLWithPath: "/tmp/flug2.igc")]
        #expect(FileConverter.suggestedFileName(for: urls) == "flug1.gpx")
        #expect(FileConverter.suggestedFileName(for: [URL(fileURLWithPath: "/tmp/track.tar.gz")]) == "track.tar.gpx")
        #expect(FileConverter.suggestedFileName(for: []) == "GPS.gpx")
    }

    /// Scenario "Keine Positionen".
    @Test func noPositions() async throws {
        let files = try TempFiles()
        let text = (0..<5).map { _ in nmea("GPRMC,120000,V,,,,,,,021126,,,N") }.joined(separator: "\n")
        await #expect(throws: GPSLoggerError(.noUsableData, fileName: "nofix.nmea")) {
            try await convert([try files.file("nofix.nmea", text)])
        }
    }

    /// Scenario "Kaputte GPX-Datei".
    @Test func malformedGPX() async throws {
        let files = try TempFiles()
        let text = "<?xml version=\"1.0\"?>\n<gpx version=\"1.1\">\n<wpt lat=\"1\" lon=\"2\">\n</gpx>\n"
        await #expect { try await convert([try files.file("broken.gpx", text)]) } throws: { error in
            guard let error = error as? GPSLoggerError, case .malformed(let line?) = error.kind else { return false }
            return error.fileName == "broken.gpx" && line > 0
        }
    }

    @Test func warningsOfAllGroupsAreKept() async throws {
        let files = try TempFiles()
        let bad = nmeaTrack(count: 3) + "$GPRMC,120100,A,5144.4694,N,00840.8580,E,10.0,90.0,021126,,,A*00\n"
        let igc = igcText + "B11014\n"
        let result = try await convert([try files.file("bad.nmea", bad), try files.file("short.igc", igc)])
        #expect(result.warnings.map(\.kind) == [.checksumMismatch, .malformedRecord])
        #expect(result.warnings.map(\.fileName) == ["bad.nmea", "short.igc"])
    }

    @Test func emptyPlanHasNoUsableData() async {
        await #expect(throws: GPSLoggerError.self) {
            try await FileConverter.convert(ConversionPlan(groups: [], unrecognized: ["x.pdf"]))
        }
    }

    /// Scenario "Große Datei abbrechen".
    @Test func cancellationStopsSoon() async throws {
        let files = try TempFiles()
        let line = nmea("GPGGA,120000,5144.4694,N,00840.8580,E,1,08,0.9,94.5,M,47.0,M,,") + "\n"
        let url = try files.file("big.nmea", String(repeating: line, count: 600_000))
        let plan = try FileConverter.plan(for: [url])
        let task = Task { try await FileConverter.convert(plan) }
        task.cancel()
        let start = Date()
        let result = await task.result
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(throws: CancellationError.self) { try result.get() }
    }
}

/// UTC dates for expectations.
enum UTCComponents {
    static func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }
}
