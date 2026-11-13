import Foundation
import Testing
@testable import GPSLoggerKit

private let namespace = "http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"

private func tcx(_ body: String) -> String {
    "<?xml version=\"1.0\"?><TrainingCenterDatabase xmlns=\"\(namespace)\" "
        + "xmlns:ns3=\"http://www.garmin.com/xmlschemas/ActivityExtension/v2\">\(body)</TrainingCenterDatabase>"
}

private func activity(_ tracks: [String]) -> String {
    "<Activity Sport=\"Running\"><Id>2026-05-01T08:00:00Z</Id>"
        + tracks.map { "<Lap StartTime=\"2026-05-01T08:00:00Z\"><Track>\($0)</Track></Lap>" }.joined()
        + "</Activity>"
}

private func trackpoint(_ i: Int, lat: String? = nil, time: String? = "2026-05-01T08:00:00Z") -> String {
    let position = "<Position><LatitudeDegrees>\(lat ?? String(50 + Double(i) / 1000))</LatitudeDegrees>"
        + "<LongitudeDegrees>8</LongitudeDegrees></Position>"
    return "<Trackpoint>\(time.map { "<Time>\($0)</Time>" } ?? "")\(position)</Trackpoint>"
}

private func read(_ text: String, name: String = "t.tcx") throws -> ImportResult {
    try TCXFileFormat().read([FileInput(name: name, data: Data(text.utf8))])
}

private func fixture(_ name: String) throws -> FileInput {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try FileInput.load(url)
}

@Suite("TCX import")
struct TCXTests {
    /// Scenario "Zwei Runden".
    @Test func lapsBecomeSegments() throws {
        let points = (0..<10).map { trackpoint($0) }.joined()
        let result = try read(tcx("<Activities>\(activity([points, points]))</Activities>"))
        #expect(result.recording.tracks.count == 1)
        #expect(result.recording.tracks[0].segments.map(\.points.count) == [10, 10])
        #expect(result.recording.tracks[0].name == nil)
    }

    /// Scenario "Zwei Aktivitäten".
    @Test func activitiesBecomeTracksInOrder() throws {
        let first = activity([trackpoint(1)])
        let second = activity([trackpoint(2) + trackpoint(3)])
        let result = try read(tcx("<Activities>\(first)\(second)</Activities>"))
        #expect(result.recording.tracks.map(\.pointCount) == [1, 2])
    }

    /// Scenarios "Punkt mit Geschwindigkeit", "Pause ohne Position", "Workout" (fixture).
    @Test func activityFixture() throws {
        let result = try TCXFileFormat().read([fixture("activity.tcx")])
        let track = try #require(result.recording.tracks.first)
        #expect(result.recording.tracks.count == 1)
        #expect(track.segments.map(\.points.count) == [2, 2])
        let first = track.segments[0].points[0]
        #expect(first.latitude == 53.55 && first.longitude == 9.99)
        #expect(first.elevation == 12.5)
        #expect(first.time == ISO8601.date("2026-05-01T08:00:00Z"))
        #expect(first.quality.speed == 3.2)
        #expect(track.segments[0].points[1].quality.speed == nil)
        #expect(result.recording.waypoints.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    /// Scenario "Ungültige Breite".
    @Test func invalidLatitudeIsAWarning() throws {
        let result = try read(tcx("<Activities>\(activity([trackpoint(1) + trackpoint(2, lat: "95")]))</Activities>"))
        #expect(result.recording.trackPointCount == 1)
        #expect(result.warnings.map(\.kind) == [.invalidCoordinate])
    }

    @Test func unreadableNumberIsAWarning() throws {
        let result = try read(tcx("<Activities>\(activity([trackpoint(1) + trackpoint(2, lat: "x")]))</Activities>"))
        #expect(result.recording.trackPointCount == 1)
        #expect(result.warnings.map(\.kind) == [.malformedRecord])
    }

    /// Scenario "Fehlende Zeit".
    @Test func missingTimeIsAWarning() throws {
        let result = try read(tcx("<Activities>\(activity([trackpoint(1, time: nil)]))</Activities>"))
        #expect(result.recording.tracks[0].segments[0].points[0].time == nil)
        #expect(result.warnings.map(\.kind) == [.missingDate])
    }

    /// Scenario "Kurs mit Kurspunkten".
    @Test func courseFixture() throws {
        let result = try TCXFileFormat().read([fixture("course.tcx")])
        #expect(result.recording.tracks.map(\.name) == ["Elbe"])
        #expect(result.recording.tracks[0].pointCount == 3)
        #expect(result.recording.waypoints.map(\.name) == ["Fähre", "Ziel"])
        let ferry = result.recording.waypoints[0]
        #expect(ferry.comment == "Abfahrt jede halbe Stunde")
        #expect(ferry.elevation == 101)
        #expect(ferry.time == ISO8601.date("2026-06-01T10:01:00Z"))
        #expect(result.recording.waypoints[1].elevation == nil)
        #expect(result.warnings.isEmpty)
    }

    @Test func multiSportSessionIsIgnored() throws {
        let multi = "<MultiSportSession><Id>2026-05-01T08:00:00Z</Id><FirstSport>\(activity([trackpoint(1)]))</FirstSport></MultiSportSession>"
        let result = try read(tcx("<Activities>\(multi)\(activity([trackpoint(2)]))</Activities>"))
        #expect(result.recording.tracks.count == 1)
        #expect(result.warnings.isEmpty)
    }

    @Test func prefixedElementsAreRead() throws {
        let text = "<t:TrainingCenterDatabase xmlns:t=\"\(namespace)\"><t:Activities><t:Activity><t:Lap><t:Track>"
            + "<t:Trackpoint><t:Time>2026-05-01T08:00:00Z</t:Time><t:Position><t:LatitudeDegrees>1</t:LatitudeDegrees>"
            + "<t:LongitudeDegrees>2</t:LongitudeDegrees></t:Position></t:Trackpoint>"
            + "</t:Track></t:Lap></t:Activity></t:Activities></t:TrainingCenterDatabase>"
        #expect(try read(text).recording.trackPointCount == 1)
    }

    /// Scenario "Abgeschnittene Datei".
    @Test func truncatedFileIsAnErrorWithLine() {
        let text = tcx("<Activities>\(activity([trackpoint(1)]))</Activities>")
        let truncated = String(text.prefix(text.count - 120)).replacingOccurrences(of: "><", with: ">\n<")
        #expect {
            try read(truncated)
        } throws: { error in
            guard let error = error as? GPSLoggerError, case .malformed(let line) = error.kind else { return false }
            return error.fileName == "t.tcx" && line != nil
        }
    }

    @Test func otherRootIsAnError() {
        #expect(throws: GPSLoggerError.self) { try read("<gpx></gpx>") }
    }

    /// Scenarios "TCX mit Endung .xml" and "GPX bleibt GPX".
    @Test func detection() throws {
        let activity = try fixture("activity.tcx").data
        #expect(FileFormats.detect(prefix: activity, fileName: "export.xml")?.id == .tcx)
        #expect(FileFormats.detect(prefix: activity, fileName: "export")?.id == .tcx)
        let gpx = try fixture("garmin-oregon.gpx").data
        #expect(FileFormats.detect(prefix: gpx, fileName: "track.tcx")?.id == .gpx)
    }

    @Test func largeFileStopsSoonAfterCancellation() async throws {
        let points = String(repeating: trackpoint(1), count: 400_000)
        let big = FileInput(name: "big.tcx", data: Data(tcx("<Activities>\(activity([points]))</Activities>").utf8))
        #expect(big.data.count > 50_000_000)
        let task = Task { try await FileFormats.read([big], format: TCXFileFormat()) }
        task.cancel()
        let start = Date()
        let result = await task.result
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(throws: CancellationError.self) { try result.get() }
    }
}
