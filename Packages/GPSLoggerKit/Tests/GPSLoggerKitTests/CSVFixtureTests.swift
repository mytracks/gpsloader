import Foundation
import Testing
@testable import GPSLoggerKit

private func fixture(_ name: String) throws -> FileInput {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try FileInput.load(url)
}

private func readDetected(_ name: String, as id: FileFormatID) throws -> ImportResult {
    let input = try fixture(name)
    let format = try #require(FileFormats.detect(prefix: input.data, fileName: name))
    #expect(format.id == id)
    return try FileFormats.readSynchronously([input], format: format, options: ImportOptions(correctWeekRollover: false))
}

private func date(_ text: String) -> Date? { ISO8601.date(text) }

private func close(_ a: Double?, _ b: Double) -> Bool {
    guard let a else { return false }
    return abs(a - b) < 1e-6
}

/// The expected values are those of the gpsbabel 1.7.0 binary for the same files (black box, design D1 and
/// task 5.3); deviations are listed in PROVENANCE.md.
@Suite("Fixtures of CSV loggers")
struct CSVFixtureTests {
    @Test func v900SimpleMode() throws {
        let result = try readDetected("v900-simple.csv", as: .v900)
        #expect(result.recording.tracks.map(\.name) == ["v900-simple"])
        let points = try #require(result.recording.tracks.first?.segments.first?.points)
        #expect(points.count == 6)
        #expect(points.first?.latitude == 50.01 && points.first?.longitude == 8.02)
        #expect(points.last?.latitude == 50.01025 && points.last?.longitude == 8.0202)
        #expect(points.map(\.time) == ["2026-11-02T23:59:57Z", "2026-11-02T23:59:58Z", "2026-11-02T23:59:59Z",
                                       "2026-11-03T00:00:00Z", "2026-11-03T00:00:01Z", "2026-11-03T00:00:02Z"].map(date))
        #expect(points.map(\.elevation) == [120, 121, 122, 123, 124, -3])
        #expect(close(points[1].quality.speed, 5) && close(points[5].quality.speed, 5.833333))
        #expect(points.map(\.quality.course) == [0, 32, 32, 33, 34, 35])
        #expect(points.allSatisfy { $0.quality.fix == nil })
        let waypoints = result.recording.waypoints
        #expect(waypoints.map(\.name) == ["POI 1", "VOX00005.WAV"])
        #expect(waypoints.map(\.time) == [date("2026-11-02T23:59:59Z"), date("2026-11-03T00:00:01Z")])
        #expect(waypoints.map(\.elevation) == [122, 124])
        #expect(waypoints.first?.latitude == 50.0101 && waypoints.first?.longitude == 8.02008)
        #expect(result.warnings.isEmpty)
    }

    @Test func v900ProfessionalMode() throws {
        let result = try readDetected("v900-pro.csv", as: .v900)
        let points = try #require(result.recording.tracks.first?.segments.first?.points)
        #expect(points.count == 3)
        #expect(points.map(\.time) == ["2026-11-04T08:15:00Z", "2026-11-04T08:15:01Z", "2026-11-04T08:15:02Z"].map(date))
        #expect(points.map(\.elevation) == [200, 201, 202])
        #expect(close(points[0].quality.speed, 1.388889) && close(points[2].quality.speed, 2.5))
        #expect(points.map(\.quality.course) == [90, 91, 92])
        // gpsbabel reports the third point as 3d; VALID = DGPS is read as dgps here (PROVENANCE.md).
        #expect(points.map(\.quality.fix) == [.threeD, .twoD, .dgps])
        #expect(points.map(\.quality.pdop) == [2.1, 3.4, 1.5])
        #expect(points.map(\.quality.hdop) == [1.2, 2.5, 0.9])
        #expect(points.map(\.quality.vdop) == [1.8, 2.3, 1.2])
        #expect(result.recording.waypoints.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    @Test(arguments: ["iblue747.csv", "iblue757.csv"])
    func iBlueExport(name: String) throws {
        let result = try readDetected(name, as: .iblueCSV)
        #expect(result.recording.tracks.map(\.name) == [(name as NSString).deletingPathExtension])
        let points = try #require(result.recording.tracks.first?.segments.first?.points)
        #expect(points.count == 4)
        #expect(points.first?.latitude == 50.03 && points.first?.longitude == 8.04)
        #expect(points.last?.latitude == 50.0303 && points.last?.longitude == 8.04045)
        #expect(points.map(\.time) == ["09:00:00", "09:00:05", "09:00:10", "09:00:15"].map { date("2026-11-05T\($0)Z") })
        #expect(points.map(\.elevation) == [150, 151, 152, 153])
        #expect(close(points[0].quality.speed, 1.5) && close(points[1].quality.speed, 2.5)
                && close(points[2].quality.speed, 3) && close(points[3].quality.speed, 0))
        #expect(points.map(\.quality.fix) == [.threeD, .threeD, .twoD, nil])
        #expect(points.map(\.quality.satellites) == [8, 9, 5, nil])
        #expect(points.map(\.quality.hdop) == [1.1, 1.0, 2.2, nil])
        #expect(points.map(\.quality.vdop) == [1.6, 1.5, 3.1, nil])
        #expect(points.map(\.quality.pdop) == [1.9, 1.8, 3.8, nil])
        #expect(result.warnings.isEmpty)
    }

    /// The GPX written from every fixture is valid against the GPX 1.1 schema.
    #if os(macOS)
    @Test(arguments: ["v900-simple.csv", "v900-pro.csv", "iblue747.csv", "iblue757.csv"])
    func gpxIsSchemaValid(name: String) throws {
        let input = try fixture(name)
        let format = try #require(FileFormats.detect(prefix: input.data, fileName: name))
        let result = try FileFormats.readSynchronously([input], format: format)
        let gpx = GPXWriter(creator: "GPSLoggerKit tests").data(for: result.recording, createdAt: Date())
        try GPXSchemaValidator.validate(gpx)
    }
    #endif
}
