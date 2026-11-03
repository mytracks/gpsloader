import Foundation
import Testing
import GPSLoggerKit
import LoggerCore
@testable import GPXExport

@Suite("GPXFileName")
struct GPXFileNameTests {
    /// 2026-11-02 14:30:05 UTC
    private let date = Date(timeIntervalSince1970: 1_793_629_805)

    /// Scenario "Erfolgreiches Auslesen": name with device, date and time.
    @Test func containsDeviceDateAndTime() {
        let name = GPXFileName.suggested(device: "Gerätename", date: date, timeZone: TimeZone(identifier: "UTC")!)
        #expect(name == "Gerätename 2026-11-02 14-30.gpx")
    }

    @Test func usesTheGivenTimeZone() {
        let name = GPXFileName.suggested(device: "Qstarz", date: date, timeZone: TimeZone(identifier: "Europe/Berlin")!)
        #expect(name == "Qstarz 2026-11-02 15-30.gpx")
    }

    @Test func replacesInvalidCharacters() {
        let name = GPXFileName.suggested(device: "GT-11/BGT-11: Logger", date: date, timeZone: TimeZone(identifier: "UTC")!)
        #expect(name == "GT-11-BGT-11- Logger 2026-11-02 14-30.gpx")
        #expect(GPXFileName.suggested(device: " ", date: date, timeZone: TimeZone(identifier: "UTC")!)
            == "GPS 2026-11-02 14-30.gpx")
    }
}

@Suite("GPXExport")
struct GPXExportTests {
    private let recording = Recording(tracks: [Track(name: "t", segments: [TrackSegment(points: [TrackPoint(latitude: 1, longitude: 2)])])])

    @Test func writesTheFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("out.gpx")
        let createdAt = Date(timeIntervalSince1970: 1_793_629_805)
        try GPXExport.write(recording, to: url, creator: "gpsloader 0.1.0", createdAt: createdAt)
        #expect(try Data(contentsOf: url) == GPXWriter(creator: "gpsloader 0.1.0").data(for: recording, createdAt: createdAt))
    }

    /// Write errors arrive as `LoggerError(.writeFailed)`; scenario "Ziel nicht beschreibbar".
    @Test func writeErrorsBecomeLoggerErrors() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let target = directory.appendingPathComponent("new.gpx")
        #expect {
            try GPXExport.write(recording, to: target, creator: "x")
        } throws: { error in
            (error as? LoggerError)?.kind == .writeFailed && !((error as? LoggerError)?.detail.isEmpty ?? true)
        }
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }
}
