import Foundation
import Testing
@testable import GPSLoggerKit

/// FIT time 1_100_000_000 = 2024-11-08 11:33:20 UTC (scenario "Punkt umrechnen").
private let t0: UInt32 = 1_100_000_000

private func input(_ file: FITTestFile, name: String = "ride.fit") -> FileInput {
    FileInput(name: name, data: Data(file.bytes()))
}

/// Reads without the "no usable data" check of `FileFormats`.
private func decode(_ bytes: [UInt8], name: String = "ride.fit") throws -> ImportResult {
    try FITFileFormat().read([FileInput(name: name, data: Data(bytes))])
}

private func decode(_ file: FITTestFile) throws -> ImportResult {
    try decode(file.bytes())
}

private func points(_ result: ImportResult) -> [TrackPoint] {
    result.recording.tracks.flatMap(\.segments).flatMap(\.points)
}

private func kinds(_ result: ImportResult) -> [ImportWarningKind] {
    result.warnings.map(\.kind)
}

/// An activity with `count` records, one per second, moving north.
private func activity(_ count: Int, bigEndian: Bool = false) -> FITTestFile {
    var file = FITTestFile()
    file.defineRecords(bigEndian: bigEndian)
    for i in 0..<count {
        file.record(time: t0 + UInt32(i), latitude: FITTestFile.semicircles(45 + Double(i % 1000) / 1000),
                    longitude: FITTestFile.semicircles(-90), altitude: 3000, speed: 2500)
    }
    return file
}

@Suite("FIT – checksum and encoder")
struct FITChecksumTests {
    @Test func crcMatchesTheCRC16ARCCheckValue() {
        #expect(FITCRC.checksum(Array("123456789".utf8)) == 0xBB3D)
    }

    @Test func encodedFileHasValidHeaderAndChecksums() {
        let bytes = activity(3).bytes()
        #expect(bytes[0] == 14)
        #expect(Array(bytes[8..<12]) == Array(".FIT".utf8))
        // CRC over a whole file including its CRC is 0.
        #expect(FITCRC.checksum(bytes) == 0)
        #expect(FITCRC.checksum(bytes[0..<14]) == 0)
    }
}

@Suite("FIT – file structure")
struct FITStructureTests {
    /// Scenario "Punkt umrechnen".
    @Test func recordIsConverted() throws {
        var file = FITTestFile()
        file.defineRecords()
        file.record(time: t0, latitude: 536_870_912, longitude: -1_073_741_824, altitude: 3000, speed: 2500)
        let result = try decode(file)
        let point = try #require(points(result).first)
        #expect(point.latitude == 45)
        #expect(point.longitude == -90)
        #expect(point.elevation == 100)
        #expect(point.time == UTCTime.date(year: 2024, month: 11, day: 8, hour: 11, minute: 33, second: 20))
        #expect(point.quality.speed == 2.5)
        #expect(result.warnings.isEmpty)
    }

    /// Scenario "Big-Endian-Definition".
    @Test func bigEndianDefinitionGivesTheSamePoints() throws {
        let little = points(try decode(activity(5)))
        let big = points(try decode(activity(5, bigEndian: true)))
        #expect(little.count == 5)
        #expect(big == little)
    }

    /// Scenario "Entwicklerfelder".
    @Test func developerFieldsAreSkipped() throws {
        var file = FITTestFile()
        file.define(local: 0, global: FITTestFile.record, fields: FITTestFile.recordFields, developerFieldSizes: [3, 1])
        for i in 0..<3 {
            file.write(local: 0, [.uint32(t0 + UInt32(i)), .sint32(FITTestFile.semicircles(10 + Double(i))),
                                  .sint32(FITTestFile.semicircles(20)), .uint16(3000), .uint16(0)],
                       developerBytes: [0xAA, 0xBB, 0xCC, 0xDD])
        }
        let result = try decode(file)
        #expect(points(result).map { $0.latitude.rounded() } == [10, 11, 12])
        #expect(points(result).allSatisfy { $0.longitude.rounded() == 20 })
        #expect(result.warnings.isEmpty)
    }

    /// Scenario "Komprimierter Zeitstempel", including the wrap of the 5-bit offset.
    @Test(arguments: [t0, t0 | 0x1E])
    func compressedTimestampFollowsTheLastTimestamp(start: UInt32) throws {
        var file = FITTestFile()
        file.defineRecords()
        file.define(local: 1, global: FITTestFile.record, fields: [(0, .sint32(0)), (1, .sint32(0))])
        file.record(time: start, latitude: FITTestFile.semicircles(1), longitude: FITTestFile.semicircles(2))
        file.write(local: 1, [.sint32(FITTestFile.semicircles(1.1)), .sint32(FITTestFile.semicircles(2))],
                   compressedTime: UInt8((start + 3) & 0x1F))
        let times = points(try decode(file)).map(\.time)
        #expect(times.count == 2)
        let first = try #require(times[0])
        #expect(times[1] == first.addingTimeInterval(3))
    }

    /// Scenario "Verkettete Dateien".
    @Test func chainedFilesAreAllRead() throws {
        let bytes = activity(4).bytes() + activity(6).bytes()
        let result = try decode(bytes)
        #expect(points(result).count == 10)
        #expect(result.warnings.isEmpty)
    }

    @Test func trailingBytesAfterTheLastFileAreIgnored() throws {
        let result = try decode(activity(4).bytes() + [0, 1, 2])
        #expect(points(result).count == 4)
        #expect(result.warnings.isEmpty)
    }

    @Test func twelveByteHeaderWithoutHeaderCRC() throws {
        var file = activity(3)
        file.headerSize = 12
        #expect(points(try decode(file)).count == 3)
    }

    @Test func invalidAltitudeIsMissing() throws {
        var file = FITTestFile()
        file.defineRecords()
        file.record(time: t0, latitude: FITTestFile.semicircles(1), longitude: FITTestFile.semicircles(2), altitude: nil)
        let point = try #require(points(try decode(file)).first)
        #expect(point.elevation == nil)
        #expect(point.quality.speed == nil)
    }
}

@Suite("FIT – damaged files")
struct FITDamageTests {
    /// Scenario "Abgeschnittene Aktivität".
    @Test func truncatedActivityKeepsTheBeginning() throws {
        var bytes = activity(100).bytes()
        // Header (14) + definition (6 + 5 * 3 = 21); each record is 1 + 16 bytes. Cut inside record 61.
        let cut = 14 + 21 + 60 * 17 + 5
        bytes = Array(bytes[0..<cut])
        let result = try decode(bytes)
        #expect(points(result).count == 60)
        #expect(kinds(result) == [.truncatedFile])
        #expect(result.warnings[0].message(localization: "de").contains("ride.fit"))
    }

    /// Scenario "Unvollständige Binärdatei" (spec logger-kit): only the CRC is missing.
    @Test func missingFileCRCIsTruncation() throws {
        let bytes = activity(10).bytes().dropLast(2)
        let result = try decode(Array(bytes))
        #expect(points(result).count == 10)
        #expect(kinds(result) == [.truncatedFile])
    }

    /// Scenario "Undefinierte Nachrichtenart".
    @Test func undefinedLocalTypeStopsDecoding() throws {
        var file = activity(10)
        file.appendRaw([0x05, 1, 2, 3])
        let result = try decode(file)
        #expect(points(result).count == 10)
        #expect(kinds(result) == [.malformedRecord])
    }

    /// Scenario "Falsche Prüfsumme".
    @Test func wrongFileChecksumIsAWarning() throws {
        var bytes = activity(20).bytes()
        bytes[bytes.count - 1] ^= 0xFF
        let result = try decode(bytes)
        #expect(points(result).count == 20)
        #expect(kinds(result) == [.fileChecksumMismatch])
    }

    @Test func wrongHeaderChecksumIsAWarning() throws {
        var bytes = activity(5).bytes()
        bytes[12] ^= 0xFF
        let result = try decode(bytes)
        #expect(points(result).count == 5)
        // The file CRC covers the header too.
        #expect(kinds(result) == [.fileChecksumMismatch])
        #expect(result.warnings[0].count == 2)
    }

    /// Scenario "Ungültiger Kopf".
    @Test func invalidHeaderIsAnError() {
        let bytes = activity(3).bytes(headerSizeByte: 20)
        #expect {
            try decode(bytes)
        } throws: { error in
            guard let error = error as? GPSLoggerError, case .malformed = error.kind else { return false }
            return error.fileName == "ride.fit"
        }
    }

    @Test func outOfRangeLatitudeIsAWarning() throws {
        var file = activity(2)
        file.record(time: t0 + 10, latitude: 1_100_000_000, longitude: 0)
        let result = try decode(file)
        #expect(points(result).count == 2)
        #expect(kinds(result) == [.invalidCoordinate])
    }
}

@Suite("FIT – tracks, segments and courses")
struct FITTrackTests {
    /// Scenario "Erweiterte Höhe".
    @Test func enhancedAltitudeAndSpeedWin() throws {
        var file = FITTestFile()
        file.define(local: 0, global: FITTestFile.record, fields: [
            (253, .uint32(0)), (0, .sint32(0)), (1, .sint32(0)), (2, .uint16(0)), (78, .uint32(0)),
            (6, .uint16(0)), (73, .uint32(0)),
        ])
        file.write(local: 0, [.uint32(t0), .sint32(0), .sint32(0), .uint16(3000), .uint32(3500), .uint16(1000), .uint32(4000)])
        let point = try #require(points(try decode(file)).first)
        #expect(point.elevation == 200)
        #expect(point.quality.speed == 4)
    }

    /// Scenario "Nur Herzfrequenz".
    @Test func recordWithoutPositionIsSkippedSilently() throws {
        var file = activity(2)
        file.define(local: 2, global: FITTestFile.record, fields: [(253, .uint32(0)), (3, .uint8(0))])
        file.write(local: 2, [.uint32(t0 + 5), .uint8(140)])
        let result = try decode(file)
        #expect(points(result).count == 2)
        #expect(result.warnings.isEmpty)
    }

    /// Scenario "Relative Gerätezeit".
    @Test func relativeDeviceTimeHasNoDate() throws {
        var file = FITTestFile()
        file.defineRecords()
        file.record(time: 1000, latitude: 0, longitude: 0)
        file.record(time: 1001, latitude: 0, longitude: 0)
        let result = try decode(file)
        #expect(points(result).allSatisfy { $0.time == nil })
        #expect(result.warnings == [ImportWarning(kind: .missingDate, count: 2, fileName: "ride.fit", firstLine: 2)])
    }

    /// Scenario "Pause in einer Aktivität".
    @Test func timerStopAndStartSplitSegments() throws {
        var file = FITTestFile()
        file.defineRecords()
        file.defineEvents()
        file.timer(time: t0, type: 0)
        for i in 0..<10 { file.record(time: t0 + UInt32(i), latitude: Int32(i), longitude: 0) }
        file.timer(time: t0 + 10, type: 1)
        file.timer(time: t0 + 100, type: 0)
        for i in 0..<5 { file.record(time: t0 + 100 + UInt32(i), latitude: Int32(i), longitude: 0) }
        file.timer(time: t0 + 200, type: 4)
        let track = try #require(try decode(file).recording.tracks.first)
        #expect(track.segments.map(\.points.count) == [10, 5])
        #expect(track.name == "ride")
    }

    @Test func stopAllWithoutStartOpensANewSegment() throws {
        var file = FITTestFile()
        file.defineRecords()
        file.defineEvents()
        for i in 0..<3 { file.record(time: t0 + UInt32(i), latitude: 0, longitude: 0) }
        file.timer(time: t0 + 3, type: 4)
        file.timer(time: t0 + 4, type: 4)
        for i in 0..<2 { file.record(time: t0 + 10 + UInt32(i), latitude: 0, longitude: 0) }
        let track = try #require(try decode(file).recording.tracks.first)
        #expect(track.segments.map(\.points.count) == [3, 2])
    }

    /// Scenarios "Kursdatei" and "Kurspunkt".
    @Test func courseNameAndCoursePoints() throws {
        var file = activity(5)
        file.define(local: 3, global: FITTestFile.course, fields: [(5, .string("", size: 16))])
        file.write(local: 3, [.string("Runde Alster", size: 16)])
        file.define(local: 4, global: FITTestFile.coursePoint, fields: [
            (1, .uint32(0)), (2, .sint32(0)), (3, .sint32(0)), (6, .string("", size: 8)),
        ])
        file.write(local: 4, [.uint32(t0 + 2), .sint32(FITTestFile.semicircles(45.002)),
                              .sint32(FITTestFile.semicircles(-90)), .string("Wende", size: 8)])
        let recording = try decode(file).recording
        #expect(recording.tracks.map(\.name) == ["Runde Alster"])
        let waypoint = try #require(recording.waypoints.first)
        #expect(recording.waypoints.count == 1)
        #expect(waypoint.name == "Wende")
        #expect(abs(waypoint.latitude - 45.002) < 1e-6)
        #expect(waypoint.time == Date(timeIntervalSince1970: TimeInterval(t0 + 2) + 631_065_600))
    }

    /// Scenario "Zwei Dateien".
    @Test func twoFilesGiveTwoTracksInOrder() throws {
        let result = try FileFormats.readSynchronously([input(activity(3), name: "b.fit"), input(activity(2), name: "a.fit")],
                                                       format: FITFileFormat(),
                                                       options: ImportOptions(correctWeekRollover: false))
        #expect(result.recording.tracks.map(\.name) == ["b", "a"])
        #expect(result.recording.tracks.map(\.pointCount) == [3, 2])
    }

    @Test func fileWithoutPositionsHasNoUsableData() {
        var file = FITTestFile()
        file.defineEvents()
        file.timer(time: t0, type: 0)
        #expect {
            try FileFormats.readSynchronously([input(file)], format: FITFileFormat())
        } throws: { error in
            (error as? GPSLoggerError)?.kind == .noUsableData
        }
    }

    @Test func largeFileStopsSoonAfterCancellation() async throws {
        var file = activity(1)
        file.repeatLastMessage(size: 17, count: 1_000_000)
        let big = FileInput(name: "big.fit", data: Data(file.bytes(checksum: false)))
        #expect(big.data.count > 17_000_000)
        let task = Task { try await FileFormats.read([big], format: FITFileFormat()) }
        task.cancel()
        let start = Date()
        let result = await task.result
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(throws: CancellationError.self) { try result.get() }
    }
}

@Suite("FIT – test encoder")
struct FITEncoderTests {
    @Test func repeatedMessagesDecodeAsSeparatePoints() throws {
        var file = activity(1)
        file.repeatLastMessage(size: 17, count: 1000)
        let result = try FITFileFormat().read([FileInput(name: "r.fit", data: Data(file.bytes()))])
        #expect(result.recording.trackPointCount == 1000)
        #expect(result.warnings.isEmpty)
    }
}

@Suite("FIT – detection")
struct FITDetectionTests {
    /// Scenario "Endung fehlt".
    @Test func detectedWithoutExtension() {
        #expect(FileFormats.detect(prefix: Data(activity(2).bytes()), fileName: "ride")?.id == .fit)
        #expect(FileFormats.detect(prefix: Data(activity(2).bytes()), fileName: "ride.gpx")?.id == .fit)
    }

    /// Scenario "Andere Binärdatei".
    @Test func otherBinaryIsNotFIT() {
        var bytes = activity(2).bytes()
        bytes[9] = 0x58
        #expect(FileFormats.detect(prefix: Data(bytes), fileName: "ride.fit") == nil)
    }

    @Test func tooShortIsNotFIT() {
        #expect(!FITFileFormat().matches(prefix: Data(activity(2).bytes().prefix(11))))
    }
}
