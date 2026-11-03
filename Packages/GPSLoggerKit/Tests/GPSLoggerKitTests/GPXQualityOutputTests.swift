import Foundation
import Testing
@testable import GPSLoggerKit

@Suite("GPXWriter – quality values", .serialized)
struct GPXQualityOutputTests {
    private let writer = GPXWriter(creator: "test")
    private let t0 = Date(timeIntervalSince1970: 1_793_629_805)

    private var recording: Recording {
        let quality = PositionQuality(speed: 12.5, course: 270, satellites: 8, hdop: 0.9, vdop: 1.25, pdop: 1.5, fix: .threeD)
        return Recording(
            tracks: [Track(name: "q", segments: [TrackSegment(points: [
                TrackPoint(latitude: 51.7, longitude: 8.6, elevation: 94, time: t0, quality: quality),
                TrackPoint(latitude: 51.8, longitude: 8.7, quality: PositionQuality(satellites: 4)),
            ])])],
            waypoints: [Waypoint(latitude: 1, longitude: 2, name: "W", comment: "c", quality: PositionQuality(fix: .dgps))]
        )
    }

    /// Scenario "Punkt mit Qualitätsangaben".
    @Test func qualityValuesInSchemaOrder() throws {
        let text = writer.document(for: recording, createdAt: t0)
        let expected = [
            "        <time>2026-11-02T14:30:05Z</time>",
            "        <fix>3d</fix>",
            "        <sat>8</sat>",
            "        <hdop>0.9</hdop>",
            "        <vdop>1.25</vdop>",
            "        <pdop>1.5</pdop>",
            "      </trkpt>",
        ].joined(separator: "\n")
        #expect(text.contains(expected))
        #expect(text.contains("<trkpt lat=\"51.8\" lon=\"8.7\">\n        <sat>4</sat>\n      </trkpt>"))
        #expect(text.contains("<cmt>c</cmt>\n    <fix>dgps</fix>\n  </wpt>"))
        #if os(macOS)
        try GPXSchemaValidator.validate(writer.data(for: recording, createdAt: t0))
        #endif
    }

    /// Scenario "Geschwindigkeit wird nicht ausgegeben".
    @Test func speedAndCourseAreNotWritten() {
        let text = writer.document(for: recording, createdAt: t0)
        #expect(!text.contains("speed"))
        #expect(!text.contains("course"))
        #expect(!text.contains("extensions"))
    }
}
