import Foundation
import Testing
@testable import GPSLoggerKit

@Suite("Data model")
struct ModelTests {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func pointsWithSameValuesAreEqual() {
        let a = TrackPoint(latitude: 51.741158, longitude: 8.680967, elevation: 94, time: date)
        let b = TrackPoint(latitude: 51.741158, longitude: 8.680967, elevation: 94, time: date)
        #expect(a == b)
        #expect(a != TrackPoint(latitude: 51.741158, longitude: 8.680967, elevation: nil, time: date))
    }

    @Test func recordingWithoutPointsAndWaypointsIsEmpty() {
        #expect(Recording().isEmpty)
        #expect(Recording(tracks: [Track(name: "x", segments: [TrackSegment()])]).isEmpty)
    }

    @Test func recordingWithOnlyWaypointsIsNotEmpty() {
        let recording = Recording(waypoints: [Waypoint(latitude: 1, longitude: 2, name: "WPT")])
        #expect(!recording.isEmpty)
    }

    @Test func pointCountsSumOverSegmentsAndTracks() {
        let segment = TrackSegment(points: Array(repeating: TrackPoint(latitude: 1, longitude: 2), count: 3))
        let track = Track(name: "t", segments: [segment, segment])
        let recording = Recording(tracks: [track, track])
        #expect(track.pointCount == 6)
        #expect(recording.trackPointCount == 12)
        #expect(!recording.isEmpty)
    }
}

@Suite("Data model – quality")
struct ModelQualityTests {
    /// Scenario "Punkt nur mit Koordinaten".
    @Test func pointWithOnlyCoordinatesHasNoOtherValues() {
        let point = TrackPoint(latitude: 51.7, longitude: 8.6)
        #expect(point.elevation == nil)
        #expect(point.time == nil)
        #expect(point.quality.isEmpty)
        #expect(point.quality.speed == nil && point.quality.course == nil)
        #expect(point.quality.satellites == nil && point.quality.fix == nil)
        #expect(point.quality.hdop == nil && point.quality.vdop == nil && point.quality.pdop == nil)
    }

    @Test func qualityWithAnyValueIsNotEmpty() {
        #expect(!PositionQuality(satellites: 0).isEmpty)
        #expect(!PositionQuality(fix: FixType.none).isEmpty)
    }
}
