import Foundation
import Testing
@testable import GPSLoggerKit

/// The FIT fixtures are produced by the test encoder (design D8). To regenerate them, run the tests
/// with `GPSLOGGERKIT_WRITE_FIXTURES=1`; they are written to the source tree.
enum FITFixtures {
    static let start: UInt32 = 1_146_384_000  // 2026-04-29 08:00:00 UTC

    /// An activity with a pause: 3 + 3 records, every 10 s, moving north from 50° N, 8° E.
    static func activity() -> [UInt8] {
        var file = FITTestFile()
        file.define(local: 2, global: FITTestFile.fileID, fields: [(0, .enumeration(0))])
        file.write(local: 2, [.enumeration(4)])  // file type "activity"
        file.defineRecords()
        file.defineEvents()
        file.timer(time: start, type: 0)
        for i in 0..<6 {
            if i == 3 {
                file.timer(time: start + 25, type: 1)
                file.timer(time: start + 30, type: 0)
            }
            file.record(time: start + UInt32(i * 10), latitude: FITTestFile.semicircles(50 + Double(i) / 1000),
                        longitude: FITTestFile.semicircles(8), altitude: UInt16((100 + i + 500) * 5), speed: 3000)
        }
        file.timer(time: start + 60, type: 4)
        return file.bytes()
    }

    /// A course "Testrunde" with 4 points and the course points "Start" and "Ziel".
    static func course() -> [UInt8] {
        var file = FITTestFile()
        file.define(local: 2, global: FITTestFile.fileID, fields: [(0, .enumeration(0))])
        file.write(local: 2, [.enumeration(6)])  // file type "course"
        file.define(local: 3, global: FITTestFile.course, fields: [(5, .string("", size: 16))])
        file.write(local: 3, [.string("Testrunde", size: 16)])
        file.defineRecords()
        for i in 0..<4 {
            file.record(time: start + UInt32(i * 60), latitude: FITTestFile.semicircles(51),
                        longitude: FITTestFile.semicircles(7 + Double(i) / 1000), altitude: 3000)
        }
        file.define(local: 4, global: FITTestFile.coursePoint, fields: [
            (1, .uint32(0)), (2, .sint32(0)), (3, .sint32(0)), (6, .string("", size: 8)),
        ])
        file.write(local: 4, [.uint32(start), .sint32(FITTestFile.semicircles(51)), .sint32(FITTestFile.semicircles(7)),
                              .string("Start", size: 8)])
        file.write(local: 4, [.uint32(start + 180), .sint32(FITTestFile.semicircles(51)),
                              .sint32(FITTestFile.semicircles(7.003)), .string("Ziel", size: 8)])
        return file.bytes()
    }

    static let fixturesDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
}

private func fixture(_ name: String) throws -> FileInput {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try FileInput.load(url)
}

private func readDetected(_ name: String) throws -> (FileFormatID, ImportResult) {
    let input = try fixture(name)
    let format = try #require(FileFormats.detect(prefix: input.data, fileName: name))
    return (format.id, try FileFormats.readSynchronously([input], format: format, options: ImportOptions(correctWeekRollover: false)))
}

private func date(_ text: String) -> Date? {
    ISO8601.date(text)
}

@Suite("Fixtures of FIT, TCX and Suunto")
struct FormatFixtureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GPSLOGGERKIT_WRITE_FIXTURES"] == "1"))
    func writeFITFixtures() throws {
        try Data(FITFixtures.activity()).write(to: FITFixtures.fixturesDirectory.appendingPathComponent("activity.fit"))
        try Data(FITFixtures.course()).write(to: FITFixtures.fixturesDirectory.appendingPathComponent("course.fit"))
    }

    @Test func fitFixturesMatchTheEncoder() throws {
        #expect(try fixture("activity.fit").data == Data(FITFixtures.activity()))
        #expect(try fixture("course.fit").data == Data(FITFixtures.course()))
    }

    @Test func activityFIT() throws {
        let (id, result) = try readDetected("activity.fit")
        #expect(id == .fit)
        let track = try #require(result.recording.tracks.first)
        #expect(track.name == "activity")
        #expect(track.segments.map(\.points.count) == [3, 3])
        let all = track.segments.flatMap(\.points)
        #expect(abs(all[0].latitude - 50) < 1e-6 && abs(all[0].longitude - 8) < 1e-6)
        #expect(abs(all[5].latitude - 50.005) < 1e-6)
        #expect(all[0].time == date("2026-04-29T08:00:00Z") && all[5].time == date("2026-04-29T08:00:50Z"))
        #expect(all.map(\.elevation) == [100, 101, 102, 103, 104, 105])
        #expect(all.allSatisfy { $0.quality.speed == 3 })
        #expect(result.warnings.isEmpty)
    }

    @Test func courseFIT() throws {
        let (id, result) = try readDetected("course.fit")
        #expect(id == .fit)
        #expect(result.recording.tracks.map(\.name) == ["Testrunde"])
        let all = result.recording.tracks[0].segments.flatMap(\.points)
        #expect(all.count == 4)
        #expect(abs(all[3].longitude - 7.003) < 1e-6)
        #expect(all[3].time == date("2026-04-29T08:03:00Z"))
        #expect(result.recording.waypoints.map(\.name) == ["Start", "Ziel"])
        #expect(result.warnings.isEmpty)
    }

    @Test func activityTCX() throws {
        let (id, result) = try readDetected("activity.tcx")
        #expect(id == .tcx)
        let all = result.recording.tracks.flatMap(\.segments).flatMap(\.points)
        #expect(all.count == 4)
        #expect(all.first?.latitude == 53.55 && all.last?.latitude == 53.553)
        #expect(all.first?.time == date("2026-05-01T08:00:00Z") && all.last?.time == date("2026-05-01T08:06:00Z"))
    }

    @Test func courseTCX() throws {
        let (id, result) = try readDetected("course.tcx")
        #expect(id == .tcx)
        let all = result.recording.tracks.flatMap(\.segments).flatMap(\.points)
        #expect(all.count == 3)
        #expect(all.first?.latitude == 50 && all.last?.latitude == 50.002)
        #expect(all.first?.time == date("2026-06-01T10:00:00Z") && all.last?.time == date("2026-06-01T10:02:00Z"))
    }

    @Test func ambitSML() throws {
        let (id, result) = try readDetected("ambit.sml")
        #expect(id == .suuntoSML)
        let all = result.recording.tracks.flatMap(\.segments).flatMap(\.points)
        #expect(all.count == 8)
        #expect(abs((all.first?.latitude ?? 0) - 50) < 1e-9 && abs((all.last?.latitude ?? 0) - 50.0014) < 1e-9)
        #expect(all.first?.time == date("2026-05-01T08:00:10Z") && all.last?.time == date("2026-05-01T08:05:20Z"))
    }

    #if os(macOS)
    @Test(arguments: ["activity.fit", "course.fit", "activity.tcx", "course.tcx", "ambit.sml"])
    func gpxIsSchemaValid(name: String) throws {
        let (_, result) = try readDetected(name)
        let data = GPXWriter(creator: "GPSLoggerKit tests").data(for: result.recording, createdAt: Date())
        try GPXSchemaValidator.validate(data)
    }
    #endif
}
