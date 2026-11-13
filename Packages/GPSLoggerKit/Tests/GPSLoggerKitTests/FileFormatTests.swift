import Foundation
import Testing
@testable import GPSLoggerKit

/// A minimal format for testing the contract: one line "lat,lon" per point; a line "#" is damaged.
struct LineFormat: FileFormat {
    var id: FileFormatID { "lines" }
    var displayName: String { "Lines" }
    var fileExtensions: [String] { ["lines"] }

    func matches(prefix: Data) -> Bool {
        String(decoding: prefix, as: UTF8.self).hasPrefix("LINES")
    }

    func read(_ inputs: [FileInput]) throws -> ImportResult {
        var points: [TrackPoint] = []
        var warnings: [ImportWarning] = []
        var cancellation = CancellationCheck()
        for input in inputs {
            var collector = WarningCollector(fileName: input.name)
            for (number, line) in String(decoding: input.data, as: UTF8.self).split(separator: "\n").enumerated() {
                try cancellation.tick()
                if line == "LINES" { continue }
                let parts = line.split(separator: ",").compactMap { Double($0) }
                guard parts.count == 2 else {
                    collector.add(.malformedRecord, line: number + 1)
                    continue
                }
                points.append(TrackPoint(latitude: parts[0], longitude: parts[1]))
            }
            warnings += collector.warnings
        }
        return ImportResult(recording: Recording(tracks: points.isEmpty ? [] : [Track(segments: [TrackSegment(points: points)])]),
                            warnings: warnings)
    }
}

private func input(_ name: String, _ text: String) -> FileInput {
    FileInput(name: name, data: Data(text.utf8))
}

private let noProcessing = ImportOptions(correctWeekRollover: false)

@Suite("File format contract")
struct FileFormatTests {
    /// Scenario "Katalog abfragen".
    @Test func catalogContainsAllFormats() {
        let ids = FileFormats.all.map(\.id)
        #expect(ids == [.nmea, .gpx, .igc, .fit, .tcx, .suuntoSML, .kml, .v900, .iblueCSV])
        #expect(FileFormatID.kml.rawValue == "kml")
        #expect(FileFormatID.suuntoSML.rawValue == "suunto-sml")
        #expect(Set(ids).count == ids.count)
        #expect(FileFormats.format(withID: .nmea)?.fileExtensions.contains("nmea") == true)
        #expect(FileFormats.format(withID: .gpx)?.fileExtensions.contains("gpx") == true)
        #expect(FileFormats.format(withID: .igc)?.fileExtensions == ["igc"])
        #expect(FileFormats.format(withID: .fit)?.fileExtensions == ["fit"])
        #expect(FileFormats.format(withID: .tcx)?.fileExtensions == ["tcx", "xml"])
        #expect(FileFormats.format(withID: .suuntoSML)?.fileExtensions == ["sml", "xml"])
        #expect(FileFormats.format(withID: .kml)?.fileExtensions == ["kml", "kmz"])
        #expect(FileFormats.format(withID: .v900)?.fileExtensions == ["csv"])
        #expect(FileFormats.format(withID: .iblueCSV)?.fileExtensions == ["csv"])
        #expect(FileFormatID.iblueCSV.rawValue == "iblue-csv")
        for format in FileFormats.all {
            #expect(!format.displayName.hasPrefix("format."))
        }
    }

    /// Scenario "Zwei Dateien".
    @Test func twoFilesAreReadInTheGivenOrder() throws {
        let result = try FileFormats.readSynchronously([input("b", "LINES\n2,2\n"), input("a", "LINES\n1,1\n")],
                                                       format: LineFormat(), options: noProcessing)
        #expect(result.recording.tracks[0].segments[0].points.map(\.latitude) == [2, 1])
    }

    /// Scenario "Teilweise beschädigte Datei".
    @Test func damagedRecordsBecomeOneWarning() throws {
        let text = "LINES\n" + String(repeating: "1,2\n", count: 1000) + "#\n#\n#\n"
        let result = try FileFormats.readSynchronously([input("f.lines", text)], format: LineFormat(), options: noProcessing)
        #expect(result.recording.trackPointCount == 1000)
        #expect(result.warnings == [ImportWarning(kind: .malformedRecord, count: 3, fileName: "f.lines", firstLine: 1002)])
    }

    /// Scenario "Leere Datei".
    @Test func emptyFileIsAnError() {
        #expect {
            try FileFormats.readSynchronously([input("leer.nmea", "")], format: LineFormat())
        } throws: { error in
            (error as? GPSLoggerError) == GPSLoggerError(.empty, fileName: "leer.nmea")
                && (error as? GPSLoggerError)?.errorDescription?.contains("leer.nmea") == true
        }
    }

    @Test func fileWithoutUsableDataIsAnError() {
        #expect {
            try FileFormats.readSynchronously([input("x.lines", "LINES\n#\n")], format: LineFormat())
        } throws: { error in
            (error as? GPSLoggerError)?.kind == .noUsableData
        }
    }

    /// Scenario "Unbekannter Inhalt".
    @Test func jpegIsUnknown() {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00]) + Data(count: 500)
        #expect(FileFormats.detect(prefix: jpeg, fileName: "photo.jpg") == nil)
        #expect(FileFormats.detect(prefix: jpeg, fileName: "photo.gpx") == nil)
    }

    @Test func loadReportsUnreadableFiles() {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).nmea")
        #expect {
            try FileInput.load(url)
        } throws: { error in
            (error as? GPSLoggerError)?.kind == .unreadable
        }
    }

    @Test func loadReadsAFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).lines")
        try Data("LINES\n1,2\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let loaded = try FileInput.load(url)
        #expect(loaded.name == url.lastPathComponent)
        #expect(loaded.data == Data("LINES\n1,2\n".utf8))
    }
}

@Suite("Cancellation")
struct CancellationTests {
    @Test func contractFormatStopsOnCancellation() async throws {
        let big = input("big.lines", "LINES\n" + String(repeating: "1,2\n", count: 200_000))
        let task = Task { try await FileFormats.read([big], format: LineFormat()) }
        task.cancel()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
    }

    /// Scenario "Große Datei abbrechen": NMEA and GPX stop soon after cancellation, without a partial result.
    @Test func nmeaAndGPXStopSoonAfterCancellation() async throws {
        let nmea = input("big.nmea", String(repeating: "$GPGGA,120000,5144.4694,N,00840.8580,E,1,08,0.9,94.5,M,47.0,M,,\n", count: 600_000))
        let gpx = input("big.gpx", "<gpx>" + String(repeating: "<wpt lat=\"1\" lon=\"2\"/>", count: 600_000) + "</gpx>")
        for (file, format) in [(nmea, FileFormats.format(withID: .nmea)!), (gpx, FileFormats.format(withID: .gpx)!)] {
            let task = Task { try await FileFormats.read([file], format: format) }
            task.cancel()
            let start = Date()
            let result = await task.result
            #expect(Date().timeIntervalSince(start) < 1, "\(format.id) took too long to stop")
            #expect(throws: CancellationError.self) { try result.get() }
        }
    }
}

@Suite("Post-processing")
struct ProcessingTests {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        UTCTime.date(year: y, month: m, day: d, hour: 12)!
    }

    /// Scenario "Logger mit Wochenüberlauf".
    @Test func weekRolloverIsCorrected() {
        let recording = Recording(tracks: [Track(segments: [TrackSegment(points: [
            TrackPoint(latitude: 1, longitude: 2, time: date(2007, 3, 15)),
            TrackPoint(latitude: 1, longitude: 2, time: date(2026, 10, 1)),
            TrackPoint(latitude: 1, longitude: 2),
        ])])], waypoints: [Waypoint(latitude: 1, longitude: 2, time: date(2007, 3, 15))])
        let corrected = RecordingProcessing.correctingWeekRollover(recording, reference: date(2026, 11, 3))
        let points = corrected.tracks[0].segments[0].points
        #expect(points[0].time == date(2026, 10, 29))
        #expect(points[1].time == date(2026, 10, 1))
        #expect(points[2].time == nil)
        #expect(corrected.waypoints[0].time == date(2026, 10, 29))
    }

    @Test func doubleRolloverIsCorrectedRepeatedly() {
        let old = date(2026, 10, 29).addingTimeInterval(-2 * RecordingProcessing.rolloverInterval)
        #expect(RecordingProcessing.corrected(old, reference: date(2026, 11, 3)) == date(2026, 10, 29))
    }

    /// Scenario "Korrektur abgeschaltet".
    @Test func correctionCanBeSwitchedOff() throws {
        let nmea = "$GPRMC,120000,A,5144.4694,N,00840.8580,E,0.0,0.0,150307,,,A\n"
        let options = ImportOptions(correctWeekRollover: false, referenceDate: date(2026, 11, 3))
        let off = try FileFormats.readSynchronously([input("a.nmea", nmea)], format: NMEAFileFormat(), options: options)
        #expect(off.recording.tracks[0].segments[0].points[0].time == date(2007, 3, 15))
        let on = try FileFormats.readSynchronously([input("a.nmea", nmea)], format: NMEAFileFormat(),
                                                   options: ImportOptions(referenceDate: date(2026, 11, 3)))
        #expect(on.recording.tracks[0].segments[0].points[0].time == date(2026, 10, 29))
    }

    /// Scenario "Datei nur mit Wegpunkten".
    @Test func waypointsBecomeATrack() throws {
        var gpx = "<gpx xmlns=\"http://www.topografix.com/GPX/1/1\">"
        for i in 0..<20 { gpx += "<wpt lat=\"\(i)\" lon=\"\(i)\"><name>W\(i)</name></wpt>" }
        gpx += "</gpx>"
        let options = ImportOptions(waypointsAsTrackWhenNoTracks: true)
        let result = try FileFormats.readSynchronously([input("w.gpx", gpx)], format: GPXFileFormat(), options: options)
        #expect(result.recording.tracks.count == 1)
        #expect(result.recording.tracks[0].segments[0].points.map(\.latitude) == (0..<20).map(Double.init))
        #expect(result.recording.waypoints.count == 20)

        let without = try FileFormats.readSynchronously([input("w.gpx", gpx)], format: GPXFileFormat())
        #expect(without.recording.tracks.isEmpty)
    }

    @Test func waypointsAsTrackLeavesExistingTracksAlone() {
        let recording = Recording(tracks: [Track(segments: [TrackSegment(points: [TrackPoint(latitude: 1, longitude: 1)])])],
                                  waypoints: [Waypoint(latitude: 2, longitude: 2)])
        #expect(RecordingProcessing.waypointsAsTrack(recording) == recording)
    }
}

@Suite("Provenance")
struct ProvenanceTests {
    static let provenanceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("PROVENANCE.md")

    static func sections(in text: String) -> Set<String> {
        Set(text.split(separator: "\n").filter { $0.hasPrefix("## ") }.map { String($0.dropFirst(3)).trimmingCharacters(in: .whitespaces) })
    }

    /// Every format in the catalog has a section in PROVENANCE.md (spec `logger-kit`, "Herkunftsnachweis").
    /// Reads the file from the source tree, so it is skipped on a physical device.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: provenanceURL.path)))
    func everyFormatHasAProvenanceSection() throws {
        let sections = Self.sections(in: try String(contentsOf: Self.provenanceURL, encoding: .utf8))
        for format in FileFormats.all {
            #expect(sections.contains("`\(format.id.rawValue)`"), "PROVENANCE.md lacks a section ## `\(format.id.rawValue)`")
        }
    }

    @Test func missingSectionIsDetected() {
        let sections = Self.sections(in: "# Provenance\n\n## `nmea`\ntext\n")
        #expect(sections.contains("`nmea`"))
        #expect(!sections.contains("`gpx`"))
    }
}
