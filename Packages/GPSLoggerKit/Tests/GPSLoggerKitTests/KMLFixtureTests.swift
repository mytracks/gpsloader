import Foundation
import Testing
@testable import GPSLoggerKit

/// `tour.kmz` is produced by the test encoder (design D8). To regenerate it, run the tests with
/// `GPSLOGGERKIT_WRITE_FIXTURES=1`; it is written to the source tree.
enum KMZFixtures {
    static let document = """
    <?xml version="1.0" encoding="UTF-8"?>
    <kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2">
      <Document>
        <name>Tour im Archiv</name>
        <Placemark>
          <name>Seeweg</name>
          <gx:Track>
            <when>2026-05-04T07:30:00Z</when>
            <when>2026-05-04T07:30:30Z</when>
            <when>2026-05-04T07:31:00Z</when>
            <gx:coord>8.060000 50.050000 95</gx:coord>
            <gx:coord>8.061000 50.050500 96</gx:coord>
            <gx:coord>8.062000 50.051000 97</gx:coord>
          </gx:Track>
        </Placemark>
        <Placemark>
          <name>Steg</name>
          <description>Foto: files/steg.jpg</description>
          <Point><coordinates>8.062000,50.051000</coordinates></Point>
        </Placemark>
      </Document>
    </kml>
    """

    /// Not a real image; only its presence in the archive matters.
    static let image: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0] + [UInt8](repeating: 0x42, count: 512) + [0xFF, 0xD9]

    static func tour() -> [UInt8] {
        KMZTestFile(entries: [
            KMZTestFile.Entry("doc.kml", document),
            KMZTestFile.Entry("files/steg.jpg", bytes: image, method: 0),
        ]).bytes()
    }

    static let fixturesDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
}

private func fixture(_ name: String) throws -> FileInput {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try FileInput.load(url)
}

private func readDetected(_ name: String) throws -> ImportResult {
    let input = try fixture(name)
    let format = try #require(FileFormats.detect(prefix: input.data, fileName: name))
    #expect(format.id == .kml)
    return try FileFormats.readSynchronously([input], format: format, options: ImportOptions(correctWeekRollover: false))
}

private func date(_ text: String) -> Date? { ISO8601.date(text) }

@Suite("Fixtures of KML and KMZ")
struct KMLFixtureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GPSLOGGERKIT_WRITE_FIXTURES"] == "1"))
    func writeKMZFixture() throws {
        try Data(KMZFixtures.tour()).write(to: KMZFixtures.fixturesDirectory.appendingPathComponent("tour.kmz"))
    }

    @Test func kmzFixtureMatchesTheEncoder() throws {
        #expect(try fixture("tour.kmz").data == Data(KMZFixtures.tour()))
    }

    /// Structure of the myTracks export (design D1): Google namespace, no altitudeMode, no times.
    @Test func myTracksExport() throws {
        let result = try readDetected("mytracks.kml")
        #expect(result.recording.tracks.map(\.name) == ["Sonntagsrunde"])
        let all = result.recording.tracks[0].segments.flatMap(\.points)
        #expect(result.recording.tracks[0].segments.count == 1)
        #expect(all.map(\.elevation) == [210, 212, 209, 207, 205])
        #expect(all.first?.latitude == 50.02 && all.first?.longitude == 8.03)
        #expect(all.last?.latitude == 50.024 && all.last?.longitude == 8.034)
        #expect(all.allSatisfy { $0.time == nil })
        #expect(result.recording.waypoints.map(\.name) == ["Aussicht", "Bank"])
        #expect(result.warnings.map(\.kind) == [.missingTimes])
    }

    /// Output of the gpsbabel 1.7.0 binary for a synthetic GPX file (black box, design D1).
    @Test func gpsbabelOutput() throws {
        let result = try readDetected("gpsbabel.kml")
        #expect(result.recording.tracks.map(\.name) == ["Abendlauf"])
        let track = result.recording.tracks[0]
        #expect(track.segments.map(\.points.count) == [3, 3])
        let all = track.segments.flatMap(\.points)
        #expect(all.map(\.elevation) == [120.5, 121, 122, 123, 124, 125.25])
        #expect(all.first?.latitude == 50.01 && all.first?.longitude == 8.02)
        #expect(all.last?.latitude == 50.015 && all.last?.longitude == 8.025)
        #expect(all.map(\.time) == ["18:00:00", "18:00:10", "18:00:20", "18:01:00", "18:01:10", "18:01:20"].map {
            date("2026-05-02T\($0)Z")
        })
        #expect(result.recording.waypoints.map(\.name) == ["Brunnen"])
        #expect(result.recording.waypoints.first?.time == date("2026-05-02T18:05:00Z"))
        #expect(result.recording.waypoints.first?.elevation == 131)
        #expect(result.warnings.isEmpty)
    }

    @Test func googleMultiTrack() throws {
        let result = try readDetected("gxtrack.kml")
        #expect(result.recording.tracks.map(\.name) == ["Radtour Mai"])
        let track = result.recording.tracks[0]
        #expect(track.segments.map(\.points.count) == [3, 2])
        let all = track.segments.flatMap(\.points)
        #expect(all.map(\.elevation) == [150, 151.5, 153, 155, 156])
        #expect(all.first?.time == date("2026-05-03T09:00:00Z") && all.last?.time == date("2026-05-03T09:10:05Z"))
        #expect(all.last?.latitude == 50.0325 && all.last?.longitude == 8.0425)
        #expect(result.warnings.isEmpty)
    }

    @Test func oldGoogleEarthFile() throws {
        let result = try readDetected("earth21.kml")
        #expect(result.recording.tracks.map(\.name) == ["Wanderweg"])
        let all = result.recording.tracks[0].segments.flatMap(\.points)
        #expect(all.count == 3)
        #expect(all.allSatisfy { $0.elevation == nil })
        #expect(result.recording.waypoints.map(\.name) == ["Gipfel"])
        #expect(result.recording.waypoints.first?.elevation == 402)
        #expect(result.recording.waypoints.first?.comment == "<b>Aussicht</b> nach Süden")
        #expect(result.warnings.map(\.kind) == [.missingTimes])
    }

    @Test func kmzArchive() throws {
        let result = try readDetected("tour.kmz")
        #expect(result.recording.tracks.map(\.name) == ["Seeweg"])
        let all = result.recording.tracks[0].segments.flatMap(\.points)
        #expect(all.map(\.elevation) == [95, 96, 97])
        #expect(all.first?.time == date("2026-05-04T07:30:00Z") && all.last?.time == date("2026-05-04T07:31:00Z"))
        #expect(result.recording.waypoints.map(\.name) == ["Steg"])
        #expect(result.warnings.isEmpty)
    }

    #if os(macOS)
    @Test(arguments: ["mytracks.kml", "gpsbabel.kml", "gxtrack.kml", "earth21.kml", "tour.kmz"])
    func gpxIsSchemaValid(name: String) throws {
        let result = try readDetected(name)
        let data = GPXWriter(creator: "GPSLoggerKit tests").data(for: result.recording, createdAt: Date())
        try GPXSchemaValidator.validate(data)
    }
    #endif
}
