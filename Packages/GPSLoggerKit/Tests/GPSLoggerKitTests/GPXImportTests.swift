import Foundation
import Testing
@testable import GPSLoggerKit

private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Double) -> Date {
    UTCTime.date(year: y, month: mo, day: d, hour: h, minute: mi, second: s)!
}

private func read(_ text: String, name: String = "t.gpx") throws -> ImportResult {
    try FileFormats.readSynchronously([FileInput(name: name, data: Data(text.utf8))], format: GPXFileFormat(),
                                      options: ImportOptions(correctWeekRollover: false))
}

private func fixture(_ name: String) throws -> FileInput {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try FileInput.load(url)
}

@Suite("ISO 8601")
struct ISO8601Tests {
    /// Scenario "Zeit mit Zonenversatz".
    @Test func zoneOffset() {
        #expect(ISO8601.date("2026-11-02T15:30:05+01:00") == utc(2026, 11, 2, 14, 30, 5))
        #expect(ISO8601.date("2026-11-02T09:30:05-05:00") == utc(2026, 11, 2, 14, 30, 5))
        #expect(ISO8601.date("2026-11-02T15:30:05+0100") == utc(2026, 11, 2, 14, 30, 5))
    }

    @Test func utcAndNoZone() {
        #expect(ISO8601.date("2026-11-02T14:30:05Z") == utc(2026, 11, 2, 14, 30, 5))
        #expect(ISO8601.date("2026-11-02T14:30:05") == utc(2026, 11, 2, 14, 30, 5))
        #expect(ISO8601.date("  2026-11-02T14:30:05Z\n") == utc(2026, 11, 2, 14, 30, 5))
        #expect(ISO8601.date("2026-11-02") == utc(2026, 11, 2, 0, 0, 0))
    }

    @Test func fractions() throws {
        #expect(ISO8601.date("2026-11-02T14:30:05.25Z") == utc(2026, 11, 2, 14, 30, 5.25))
        #expect(ISO8601.date("2026-11-02T14:30:05.123Z") == utc(2026, 11, 2, 14, 30, 5.123))
        let long = try #require(ISO8601.date("2026-11-02T14:30:05.1234567891234Z"))
        #expect(abs(long.timeIntervalSince(utc(2026, 11, 2, 14, 30, 5)) - 0.123456789) < 1e-6)
    }

    @Test func yearsBefore1970() {
        #expect(ISO8601.date("1969-12-31T23:59:59.5Z") == Date(timeIntervalSince1970: -0.5))
        #expect(ISO8601.date("1900-03-01T00:00:00Z") == Date(timeIntervalSince1970: -2_203_891_200))
    }

    @Test(arguments: ["", "2026-13-01T00:00:00Z", "2026-02-30T00:00:00Z", "2026-11-02T25:00:00Z",
                      "2026-11-02T14:30Z", "2026-11-02T14:30:05.Z", "2026-11-02T14:30:05X", "yesterday",
                      "2026-11-02T14:30:05+1:00"])
    func invalidValues(text: String) {
        #expect(ISO8601.date(text) == nil)
    }

    @Test func matchesTheWriterFormat() {
        let date = utc(2026, 11, 2, 14, 30, 5.25)
        #expect(ISO8601.date(GPXText.time(date)) == date)
    }
}

@Suite("GPX import")
struct GPXImportTests {
    /// Scenario "GPX 1.0 eines älteren Garmin-Geräts".
    @Test func gpx10() throws {
        let result = try FileFormats.readSynchronously([try fixture("garmin-gpx10.gpx")], format: GPXFileFormat(),
                                                       options: ImportOptions(correctWeekRollover: false))
        let track = try #require(result.recording.tracks.first)
        #expect(result.recording.tracks.count == 1)
        #expect(track.name == "ACTIVE LOG")
        #expect(track.pointCount == 4)
        let point = track.segments[0].points[0]
        #expect(point.elevation == 94.3)
        #expect(point.time == utc(2008, 6, 14, 9, 15, 0))
        #expect(point.quality.speed == 1.5)
        #expect(point.quality.course == 45.0)
        #expect(result.warnings.isEmpty)
    }

    /// Scenario "Ohne Namensraum".
    @Test func withoutNamespace() throws {
        let result = try read("<gpx><trk><trkseg><trkpt lat=\"1\" lon=\"2\"/><trkpt lat=\"3\" lon=\"4\"/></trkseg></trk></gpx>")
        #expect(result.recording.trackPointCount == 2)
    }

    @Test func prefixedNamespace() throws {
        let text = """
        <g:gpx xmlns:g="http://www.topografix.com/GPX/1/1"><g:wpt lat="1" lon="2"><g:name>A</g:name></g:wpt></g:gpx>
        """
        #expect(try read(text).recording.waypoints.first?.name == "A")
    }

    /// Scenarios "Garmin-Datei mit Tracks, Wegpunkten und Route" and "Garmin-Erweiterungen".
    @Test func garminFileWithTracksWaypointsRouteAndExtensions() throws {
        let result = try FileFormats.readSynchronously([try fixture("garmin-oregon.gpx")], format: GPXFileFormat(),
                                                       options: ImportOptions(correctWeekRollover: false))
        #expect(result.recording.tracks.map(\.name) == ["Morgenrunde", "Nachmittag"])
        #expect(result.recording.tracks.map(\.pointCount) == [3, 2])
        #expect(result.recording.tracks[1].segments.count == 2)
        #expect(result.recording.waypoints.count == 5)
        #expect(result.recording.waypoints.map(\.name) == ["Start", "Brücke", "Café & Bäckerei", "Gipfel", "Ziel"])
        #expect(result.recording.waypoints[0].comment == "Parkplatz")
        #expect(result.warnings.isEmpty)
        let first = result.recording.tracks[0].segments[0].points[0]
        #expect(first.time == utc(2026, 10, 18, 7, 2, 11))
        #expect(first.quality == PositionQuality(satellites: 9, hdop: 0.8, fix: .threeD))
        // Route points do not show up anywhere.
        #expect(!result.recording.waypoints.contains { $0.name == "Routenpunkt" })
    }

    @Test func emptyTracksAndSegmentsAreDropped() throws {
        let result = try read("<gpx><trk><name>leer</name><trkseg/></trk><trk><trkseg><trkpt lat=\"1\" lon=\"2\"/></trkseg><trkseg/></trk></gpx>")
        #expect(result.recording.tracks.count == 1)
        #expect(result.recording.tracks[0].segments.count == 1)
    }

    /// Scenario "Punkt außerhalb des Wertebereichs".
    @Test func invalidCoordinatesAreSkipped() throws {
        let text = """
        <gpx>
          <trk><trkseg>
            <trkpt lat="51.7" lon="8.6"/>
            <trkpt lat="123.4" lon="8.6"/>
            <trkpt lat="51.7" lon="-180.5"/>
            <trkpt lat="abc" lon="8.6"/>
            <trkpt lon="8.6"/>
          </trkseg></trk>
        </gpx>
        """
        let result = try read(text)
        #expect(result.recording.trackPointCount == 1)
        #expect(result.warnings == [ImportWarning(kind: .invalidCoordinate, count: 4, fileName: "t.gpx", firstLine: 4)])
    }

    @Test func unparsableValuesAreLeftEmpty() throws {
        let result = try read("<gpx><wpt lat=\"1\" lon=\"2\"><ele>hoch</ele><time>gestern</time><fix>pps</fix></wpt></gpx>")
        let waypoint = try #require(result.recording.waypoints.first)
        #expect(waypoint.elevation == nil && waypoint.time == nil && waypoint.quality.fix == nil)
    }

    /// Scenario "Abgeschnittene Datei".
    @Test func truncatedFileIsAnErrorWithLine() throws {
        let text = "<?xml version=\"1.0\"?>\n<gpx>\n<trk><trkseg>\n<trkpt lat=\"1\" lon=\"2\">\n<ele>3</ele>\n<trkpt lat=\"1\" lo"
        #expect {
            try read(text, name: "kaputt.gpx")
        } throws: { error in
            guard let error = error as? GPSLoggerError, case .malformed(let line?) = error.kind else { return false }
            return error.fileName == "kaputt.gpx" && line >= 5
        }
    }

    @Test func otherXMLIsAnError() {
        #expect {
            try read("<kml xmlns=\"http://www.opengis.net/kml/2.2\"><Document/></kml>")
        } throws: { error in
            if case .malformed = (error as? GPSLoggerError)?.kind { return true }
            return false
        }
    }

    @Test func registeredInTheCatalog() {
        let format = FileFormats.format(withID: .gpx)
        #expect(format is GPXFileFormat)
        #expect(Set(format?.fileExtensions ?? []) == ["gpx", "xml"])
    }

    /// Scenario "GPX mit Endung `.xml`".
    @Test func detection() throws {
        let gpx = try fixture("garmin-oregon.gpx")
        #expect(FileFormats.detect(prefix: gpx.data, fileName: "export.xml")?.id == .gpx)
        #expect(FileFormats.detect(prefix: gpx.data, fileName: "export.nmea")?.id == .gpx)
        let withComment = Data("<?xml version=\"1.0\"?>\n<!-- exported -->\n<!DOCTYPE gpx>\n<gpx version=\"1.0\"></gpx>".utf8)
        #expect(GPXFileFormat().matches(prefix: withComment))
        let kml = Data("<?xml version=\"1.0\"?><kml xmlns=\"http://www.opengis.net/kml/2.2\"><Document/></kml>".utf8)
        #expect(!GPXFileFormat().matches(prefix: kml))
        #expect(FileFormats.detect(prefix: kml, fileName: "a.xml")?.id == .kml)
    }

    /// Writing and reading again yields the same model (also the iOS substitute for the XSD checks).
    @Test func roundTrip() throws {
        let quality = PositionQuality(satellites: 7, hdop: 1.2, vdop: 1.5, pdop: 2, fix: .threeD)
        let recording = Recording(
            tracks: [Track(name: "Berg & Tal <1>", segments: [
                TrackSegment(points: [
                    TrackPoint(latitude: 51.741158, longitude: 8.680967, elevation: 94.25,
                               time: utc(2026, 11, 2, 14, 30, 5.25), quality: quality),
                    TrackPoint(latitude: -33.8568, longitude: -151.2153),
                ]),
                TrackSegment(points: [TrackPoint(latitude: 0, longitude: 0, time: utc(1969, 12, 31, 23, 59, 59))]),
            ])],
            waypoints: [Waypoint(latitude: 1.5, longitude: 2.5, elevation: 3, time: utc(2026, 1, 1, 0, 0, 0),
                                 name: "Café \"Zur Post\"", comment: "a < b", quality: PositionQuality(fix: .dgps))]
        )
        let data = GPXWriter(creator: "roundtrip").data(for: recording, createdAt: utc(2026, 11, 3, 0, 0, 0))
        let result = try FileFormats.readSynchronously([FileInput(name: "r.gpx", data: data)], format: GPXFileFormat(),
                                                       options: ImportOptions(correctWeekRollover: false))
        #expect(result.recording == recording)
        #expect(result.warnings.isEmpty)
    }
}
