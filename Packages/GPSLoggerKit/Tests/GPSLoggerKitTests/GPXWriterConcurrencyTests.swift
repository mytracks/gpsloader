import Foundation
import Testing
@testable import GPSLoggerKit

/// The writer must be safe to use from many tasks at once (it has no shared mutable state).
/// This suite runs in parallel on purpose; GPXWriterTests is serialized only because XMLDocument
/// (libxml2), used there for validation, crashes when used concurrently.
@Suite("GPXWriter concurrency")
struct GPXWriterConcurrencyTests {
    @Test func concurrentDocumentsAreIdentical() async {
        let recording = Recording(tracks: [
            Track(name: "t", segments: [TrackSegment(points: (0..<500).map {
                TrackPoint(latitude: 51 + Double($0) * 0.0001, longitude: 8, elevation: 94,
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

