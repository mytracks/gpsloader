import Foundation
import Testing
import LoggerCore
@testable import GPXExport

/// The writer must be safe to use from many tasks at once (it has no shared mutable state).
/// This suite runs in parallel on purpose; GPXWriterTests is serialized only because XMLDocument
/// (libxml2), used there for validation, crashes when used concurrently.
@Suite("GPXWriter concurrency")
struct GPXWriterConcurrencyTests {
    @Test func concurrentDocumentsAreIdentical() async {
        let recording = LoggerCore.Recording(tracks: [
            LoggerCore.Track(name: "t", segments: [LoggerCore.TrackSegment(points: (0..<500).map {
                LoggerCore.TrackPoint(latitude: 51 + Double($0) * 0.0001, longitude: 8, elevation: 94,
                                      time: Date(timeIntervalSince1970: 1_793_629_805 + Double($0)))
            })]),
        ])
        let writer = GPXWriter(creator: "gpsloader test")
        let createdAt = Date(timeIntervalSince1970: 1_793_629_805)
        let reference = writer.data(for: recording, createdAt: createdAt)
        let results = await withTaskGroup(of: Bool.self) { group -> [Bool] in
            for _ in 0..<200 {
                group.addTask { writer.data(for: recording, createdAt: createdAt) == reference }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(results.count == 200)
        #expect(results.allSatisfy { $0 })
    }
}

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
