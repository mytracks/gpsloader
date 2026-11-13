// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import GPSLoggerKit
@testable import GPSLoggerKitGPL

private typealias Bit = MTKTestDump.Bit
private typealias Record = MTKTestDump.Record

private func read(_ dump: MTKTestDump, name: String = "log.bin", holux: Bool = false) throws -> ImportResult {
    let format: any FileFormat = holux ? M241BinFileFormat() : MTKBinFileFormat()
    return try FileFormats.readSynchronously([FileInput(name: name, data: dump.data)], format: format,
                                             options: ImportOptions(referenceDate: skyTraqReference))
}

private func points(_ result: ImportResult) -> [TrackPoint] {
    result.recording.tracks.flatMap { $0.segments.flatMap(\.points) }
}

private let start = Date(timeIntervalSince1970: TimeInterval(MTKTestDump.start))

@Suite("MTK dumps")
struct MTKTests {
    @Test func floatReaders() {
        let reader = ByteReader(bytes: MTKTestDump.f32(1.5) + MTKTestDump.f64(-100.25))
        #expect(reader.f32le(0) == 1.5)
        #expect(reader.f64le(4) == -100.25)
        #expect(reader.f64le(5) == nil)
    }

    /// Scenario "Datensatz eines iBlue 747".
    @Test func iBlue747Record() throws {
        var dump = MTKTestDump(mask: Bit.basic)
        dump.record(Record(time: MTKTestDump.start))
        dump.finish()
        let result = try read(dump)
        let point = try #require(points(result).first)
        #expect(point.time == start)
        #expect(point.latitude == 50 && point.longitude == 8 && point.elevation == 100)
        #expect(point.quality.fix == .threeD)
        #expect(point.quality.speed == 10)
        #expect(result.recording.tracks.map(\.name) == ["log"])
        #expect(result.warnings.isEmpty)
    }

    /// Scenario "Millisekunden".
    @Test func milliseconds() throws {
        var dump = MTKTestDump(mask: Bit.basic | Bit.millisecond)
        dump.record(Record(time: MTKTestDump.start, millisecond: 500))
        dump.finish()
        #expect(try points(read(dump)).first?.time == start.addingTimeInterval(0.5))
    }

    /// Scenario "Falsche Prüfsumme".
    @Test func wrongChecksum() throws {
        var dump = MTKTestDump(mask: Bit.basic)
        dump.record(Record(time: MTKTestDump.start))
        dump.record(Record(time: MTKTestDump.start + 1), corruptChecksum: true)
        dump.record(Record(time: MTKTestDump.start + 2))
        dump.finish()
        let result = try read(dump)
        #expect(points(result).map(\.time) == [start, start.addingTimeInterval(2)])
        #expect(result.warnings.map(\.kind) == [.checksumMismatch])
    }

    /// A record without "*" before 0xFF (power off) is skipped.
    @Test func missingStarBeforeFF() throws {
        var dump = MTKTestDump(mask: Bit.basic)
        dump.record(Record(time: MTKTestDump.start))
        var body = dump.fields(Record(time: MTKTestDump.start + 1))
        body += [0xFF, 0xFF]
        var raw = dump.bytes + body
        var second = MTKTestDump(mask: Bit.basic)
        second.record(Record(time: MTKTestDump.start + 2))
        raw += second.bytes.dropFirst(0x200)
        let result = try FileFormats.readSynchronously([FileInput(name: "a.bin", data: Data(raw))], format: MTKBinFileFormat())
        #expect(points(result).map(\.time) == [start, start.addingTimeInterval(2)])
    }

    /// Scenario "Drei Satelliten".
    @Test func satelliteData() throws {
        var dump = MTKTestDump(mask: Bit.basic | Bit.nsat | Bit.sid | Bit.elevation | Bit.azimuth | Bit.snr)
        dump.record(Record(time: MTKTestDump.start, satellitesUsed: 2, satellites: [(3, 1), (7, 1), (19, 0)]))
        dump.record(Record(time: MTKTestDump.start + 1, satellites: []))
        dump.record(Record(time: MTKTestDump.start + 2, latitude: 51, satellites: [(5, 1)]))
        dump.finish()
        let result = try read(dump)
        #expect(points(result).count == 3)
        #expect(points(result).first?.quality.satellites == 2)
        #expect(points(result).last?.latitude == 51)
        #expect(result.warnings.isEmpty)
    }

    /// Scenario "Unsinnige Position".
    @Test func bogusPosition() throws {
        var dump = MTKTestDump(mask: Bit.basic)
        dump.record(Record(time: MTKTestDump.start, valid: 0x0001, latitude: 0, longitude: 0))
        dump.record(Record(time: MTKTestDump.start + 1, valid: 0x0001, latitude: 90, longitude: 0))
        dump.record(Record(time: MTKTestDump.start + 2, valid: 0x0001, latitude: 50, longitude: -8))
        dump.record(Record(time: MTKTestDump.start + 3, valid: 0x0004, latitude: 51, longitude: 7))
        dump.finish()
        let result = try read(dump)
        #expect(points(result).map(\.latitude) == [50, 51])
        #expect(points(result).map(\.quality.fix) == [FixType.none, .dgps])
    }

    @Test(arguments: [(UInt16(0x0008), FixType?.none), (0x0040, nil), (0x0010, nil)])
    func otherFixTypes(valid: UInt16, expected: FixType?) throws {
        var dump = MTKTestDump(mask: Bit.basic)
        dump.record(Record(time: MTKTestDump.start, valid: valid))
        dump.finish()
        #expect(try points(read(dump)).first?.quality.fix == expected)
    }

    /// Scenario "Zwei Blöcke".
    @Test func twoBlocks() throws {
        var dump = MTKTestDump(mask: Bit.basic)
        for k in 0..<3 { dump.record(Record(time: MTKTestDump.start + UInt32(k))) }
        dump.endBlock()
        for k in 3..<5 { dump.record(Record(time: MTKTestDump.start + UInt32(k))) }
        dump.finish()
        #expect(try points(read(dump)).count == 5)
    }

    /// Scenario "Ungültiger erster Kopf".
    @Test func invalidFirstHeader() throws {
        var dump = MTKTestDump(mask: Bit.basic | Bit.millisecond, policy: 0x0000)
        dump.mask = Bit.basic
        dump.endBlock()
        dump.record(Record(time: MTKTestDump.start))
        dump.finish()
        let result = try FileFormats.readSynchronously([FileInput(name: "a.bin", data: dump.data)], format: MTKBinFileFormat())
        #expect(points(result).count == 1)
        #expect(result.warnings.isEmpty)
    }

    /// Scenario "Neue Formatmaske".
    @Test func newFormatMask() throws {
        var dump = MTKTestDump(mask: Bit.basic | Bit.millisecond)
        dump.record(Record(time: MTKTestDump.start, millisecond: 250))
        dump.info(0x02, UInt32(Bit.basic))
        dump.mask = Bit.basic
        dump.record(Record(time: MTKTestDump.start + 1))
        dump.finish()
        let result = try read(dump)
        #expect(points(result).map(\.time) == [start.addingTimeInterval(0.25), start.addingTimeInterval(1)])
        #expect(result.warnings.isEmpty)
    }

    /// Scenario "Logger zweimal eingeschaltet".
    @Test func loggerSwitchedOnTwice() throws {
        var dump = MTKTestDump(mask: Bit.basic)
        dump.info(0x07, 0x0106)
        dump.record(Record(time: MTKTestDump.start))
        dump.record(Record(time: MTKTestDump.start + 1))
        dump.info(0x07, 0x0106)
        dump.record(Record(time: MTKTestDump.start + 100))
        dump.finish()
        let result = try read(dump, name: "log.bin")
        #expect(result.recording.tracks.map(\.name) == ["log (1)", "log (2)"])
        #expect(result.recording.tracks.map(\.pointCount) == [2, 1])
    }

    /// Scenario "Taste gedrückt".
    @Test func buttonPress() throws {
        var dump = MTKTestDump(mask: Bit.basic | Bit.rcr)
        dump.record(Record(time: MTKTestDump.start, rcr: 0x0001))
        dump.record(Record(time: MTKTestDump.start + 1, latitude: 50.5, rcr: 0x0008))
        dump.finish()
        let result = try read(dump)
        #expect(points(result).count == 2)
        #expect(result.recording.waypoints.map(\.name) == ["POI 1"])
        #expect(result.recording.waypoints.first?.latitude == 50.5)
    }

    /// Scenario "Holux M-241".
    @Test func holuxM241() throws {
        var dump = MTKTestDump(mask: Bit.basic, device: .holux)
        dump.holux("HOLUXGR241LOGGER")
        dump.record(Record(time: MTKTestDump.start))
        dump.finish()
        let result = try read(dump, holux: true)
        let point = try #require(points(result).first)
        #expect(point.latitude == Double(Float(50)) && point.longitude == Double(Float(8)))
        #expect(point.elevation == 100)
        #expect(result.warnings.isEmpty)
    }

    /// Scenario "Holux GPSport 245".
    @Test func holuxGPSport245() throws {
        var dump = MTKTestDump(mask: Bit.basic, device: .gr245)
        dump.holux("HOLUXGR245LOGGER", spaces: true)
        dump.record(Record(time: MTKTestDump.start, height: 120, speed: 18))
        dump.finish()
        let result = try read(dump, holux: true)
        let point = try #require(points(result).first)
        #expect(point.quality.speed == 5)
        #expect(point.elevation == 120)
    }

    /// Holux waypoint after "WAYPNT".
    @Test func holuxWaypoint() throws {
        let result = try read(MTKTestDump.m241Fixture(), name: "m241.bin", holux: true)
        #expect(points(result).count == 4)
        #expect(result.recording.waypoints.map(\.name) == ["POI 1"])
        #expect(result.recording.waypoints.first?.elevation == 210)
    }

    @Test func truncatedDump() throws {
        var dump = MTKTestDump(mask: Bit.basic)
        dump.record(Record(time: MTKTestDump.start))
        dump.record(Record(time: MTKTestDump.start + 1))
        let cut = Data(dump.bytes.dropLast(5))
        let result = try FileFormats.readSynchronously([FileInput(name: "a.bin", data: cut)], format: MTKBinFileFormat())
        #expect(points(result).count == 1)
        #expect(result.warnings.map(\.kind) == [.truncatedFile])
    }

    @Test func stopsSoonAfterCancellation() async throws {
        var dump = MTKTestDump(mask: Bit.basic)
        for block in 0..<800 {
            while dump.bytes.count % 0x10000 < 0xFF00 {
                dump.record(Record(time: MTKTestDump.start + UInt32(block)))
            }
            dump.endBlock()
        }
        let file = FileInput(name: "big.bin", data: dump.data)
        #expect(file.data.count > 50_000_000)
        let task = Task { try await FileFormats.read([file], format: MTKBinFileFormat()) }
        task.cancel()
        let begin = Date()
        let result = await task.result
        #expect(Date().timeIntervalSince(begin) < 1)
        #expect(throws: CancellationError.self) { try result.get() }
    }
}

@Suite("MTK detection")
struct MTKDetectionTests {
    private let catalog = FormatCatalog.standard.adding(GPLFileFormats.all)

    /// Scenario "Abbild eines iBlue 747".
    @Test func mtkDump() {
        let prefix = Data(MTKTestDump.mtkFixture().bytes.prefix(4096))
        #expect(catalog.detect(prefix: prefix, fileName: "data.bin")?.id == .mtkBin)
        var plain = MTKTestDump(mask: Bit.basic)
        plain.record(Record(time: MTKTestDump.start))
        plain.finish()
        #expect(catalog.detect(prefix: Data(plain.bytes.prefix(4096)), fileName: "data.bin")?.id == .mtkBin)
    }

    /// Scenario "Abbild eines Holux M-241".
    @Test func holuxDump() {
        let prefix = Data(MTKTestDump.m241Fixture().bytes.prefix(4096))
        #expect(catalog.detect(prefix: prefix, fileName: "data.bin")?.id == .m241Bin)
    }

    /// Scenario "SkyTraq-Abbild" and the other way round.
    @Test func skyTraqAndMTKAreDistinct() {
        let skytraq = Data(SkyTraqTestDump.venus().bytes.prefix(4096))
        #expect(!MTKBinFileFormat().matches(prefix: skytraq) && !M241BinFileFormat().matches(prefix: skytraq))
        for dump in [MTKTestDump.mtkFixture(), MTKTestDump.m241Fixture()] {
            #expect(!SkyTraqBinFileFormat().matches(prefix: Data(dump.bytes.prefix(4096))))
        }
    }

    @Test func randomDataIsNotDetected() {
        for _ in 0..<50 {
            let random = Data((0..<4096).map { _ in UInt8.random(in: 0...255) })
            #expect(!MTKBinFileFormat().matches(prefix: random) && !M241BinFileFormat().matches(prefix: random))
        }
        var corrupt = MTKTestDump(mask: Bit.basic)
        corrupt.record(Record(time: MTKTestDump.start), corruptChecksum: true)
        #expect(!MTKBinFileFormat().matches(prefix: corrupt.data))
    }
}
