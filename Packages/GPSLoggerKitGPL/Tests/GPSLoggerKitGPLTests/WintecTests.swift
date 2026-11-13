// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import GPSLoggerKit
@testable import GPSLoggerKitGPL

/// Test encoder for Wintec files (design D7 of change wintec-file-port).
enum WintecTestFile {
    static func stamp(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> UInt32 {
        UInt32(year - 2000) << 26 | UInt32(month) << 22 | UInt32(day) << 17 | UInt32(hour) << 12 | UInt32(minute) << 6
            | UInt32(second)
    }

    static func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
    static func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8(v >> (8 * UInt32($0)) & 0xFF) } }
    static func degrees(_ v: Double) -> [UInt8] { le32(UInt32(bitPattern: Int32((v * 10_000_000).rounded()))) }

    /// TES / TK1 record: flags, time, latitude, longitude, altitude (m, Int16).
    static func record16(flags: UInt16, time: UInt32, latitude: Double, longitude: Double, altitude: Int16) -> [UInt8] {
        le16(flags) + le32(time) + degrees(latitude) + degrees(longitude) + le16(UInt16(bitPattern: altitude))
    }

    /// BIN record: time, latitude, longitude and (16 bytes) altitude in decimeters.
    static func bin(time: UInt32, latitude: Double, longitude: Double, decimeters: Int32? = nil) -> [UInt8] {
        le32(time) + degrees(latitude) + degrees(longitude) + (decimeters.map { le32(UInt32(bitPattern: $0)) } ?? [])
    }

    static func tk1(_ records: [[UInt8]]) -> [UInt8] {
        var bytes = WintecLog.tk1Magic
        bytes += [UInt8](repeating: 0, count: WintecLog.tk1DataOffset - bytes.count)
        return bytes + records.flatMap { $0 }
    }

    static let base = stamp(2026, 11, 2, 12, 0, 0)

    /// Fixture `wbt202.tes`.
    static func tesFixture() -> [UInt8] {
        var bytes: [UInt8] = []
        for k in 0..<5 {
            let flags: UInt16 = k == 2 ? 0x02 : 0x00
            let latitude = 50 + Double(k) * 0.0001
            let longitude = 8 + Double(k) * 0.0002
            bytes += record16(flags: flags, time: base + UInt32(k * 5), latitude: latitude, longitude: longitude,
                              altitude: Int16(100 + k))
        }
        return bytes
    }

    /// Fixture `wbt200.bin` (16-byte records, a new track at the third point).
    static func binFixture() -> [UInt8] {
        var bytes: [UInt8] = []
        for k in 0..<5 {
            let offset: Double = k == 2 ? 100 : 0
            let latitude: Double = offset + 50.01 + Double(k) * 0.0001
            bytes += bin(time: base + UInt32(k), latitude: latitude, longitude: 8.01, decimeters: Int32(1234 + k))
        }
        return bytes
    }

    /// Fixture `wbt201.tk1`: two tracks, a waypoint, a zero record and data after the end flag.
    static func tk1Fixture() -> [UInt8] {
        var records: [[UInt8]] = []
        for k in 0..<5 {
            let flags: UInt16 = k == 0 || k == 3 ? 0x01 : (k == 1 ? 0x02 : 0x00)
            records.append(record16(flags: flags, time: stamp(2026, 11, 2, 12, k, 0), latitude: 50.02 + Double(k) * 0.0001,
                                    longitude: 8.02, altitude: Int16(-2 + k)))
            if k == 2 { records.append([UInt8](repeating: 0, count: 16)) }
        }
        records.append(WintecTestFile.le16(0) + le32(WintecLog.tk1EndFlag) + [UInt8](repeating: 0, count: 10))
        records.append(record16(flags: 0, time: base, latitude: 10, longitude: 10, altitude: 0))
        return tk1(records)
    }
}

private func read(_ bytes: [UInt8], name: String, _ format: any FileFormat) throws -> ImportResult {
    try FileFormats.readSynchronously([FileInput(name: name, data: Data(bytes))], format: format,
                                      options: ImportOptions(referenceDate: skyTraqReference))
}

private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

@Suite("Wintec files")
struct WintecTests {
    /// Scenario "Zeitstempel".
    @Test func timeStamp() {
        let value = WintecTestFile.stamp(2026, 11, 2, 12, 30, 15)
        #expect(WintecTime.date(value) == date("2026-11-02T12:30:15Z"))
        #expect(WintecTime.isValid(value))
        #expect(!WintecTime.isValid(WintecTestFile.stamp(2026, 0, 2, 12, 30, 15)))
        #expect(!WintecTime.isValid(WintecTestFile.stamp(2003, 11, 2, 12, 30, 15)))
        #expect(WintecTime.date(WintecTestFile.stamp(2026, 2, 30, 0, 0, 0)) == nil)
    }

    /// Scenario "Aufzeichnung eines WBT-202".
    @Test func tesFile() throws {
        let bytes = (0..<3).flatMap { k in
            WintecTestFile.record16(flags: k == 1 ? 0x02 : 0, time: WintecTestFile.base + UInt32(k), latitude: 50 + Double(k),
                                    longitude: 8, altitude: -5)
        }
        let result = try read(bytes, name: "TRK0001.TES", WintecTESFileFormat())
        #expect(result.recording.tracks.map(\.name) == ["TRK0001"])
        #expect(result.recording.trackPointCount == 3)
        #expect(result.recording.waypoints.map(\.name) == ["POI 1"])
        #expect(result.recording.waypoints.first?.latitude == 51)
        #expect(result.recording.tracks.first?.segments.first?.points.first?.elevation == -5)
        #expect(result.recording.tracks.first?.segments.first?.points.first?.time == date("2026-11-02T12:00:00Z"))
    }

    /// Scenario "Abgeschnittene TES-Datei".
    @Test func truncatedTES() throws {
        let bytes = Array(WintecTestFile.tesFixture().prefix(37))
        let result = try read(bytes, name: "a.tes", WintecTESFileFormat())
        #expect(result.recording.trackPointCount == 2)
        #expect(result.warnings.map(\.kind) == [.truncatedFile])
    }

    /// Scenario "Neuer Track im Norden", plus the southern variant.
    @Test func binNewTracks() throws {
        let result = try read(WintecTestFile.binFixture(), name: "log.bin", WintecBinFileFormat())
        #expect(result.recording.tracks.map(\.pointCount) == [2, 3])
        #expect(abs((result.recording.tracks[1].segments[0].points.first?.latitude ?? 0) - 50.0102) < 1e-9)
        let south = (0..<3).flatMap { k in
            WintecTestFile.bin(time: WintecTestFile.base + UInt32(k), latitude: k == 1 ? -150 : -50, longitude: -8)
        }
        let southern = try read(south, name: "s.bin", WintecBinFileFormat())
        #expect(southern.recording.tracks.map(\.pointCount) == [1, 2])
        #expect(southern.recording.tracks[1].segments[0].points.first?.latitude == -50)
    }

    /// Scenario "Datensätze mit Höhe" and 12-byte records without height.
    @Test func binRecordLengths() throws {
        let with = try read(WintecTestFile.binFixture(), name: "a.bin", WintecBinFileFormat())
        #expect(with.recording.tracks.first?.segments.first?.points.first?.elevation == 123.4)
        let without = (0..<4).flatMap { WintecTestFile.bin(time: WintecTestFile.base + UInt32($0), latitude: 50, longitude: 8) }
        let result = try read(without, name: "b.bin", WintecBinFileFormat())
        #expect(result.recording.trackPointCount == 4)
        #expect(result.recording.tracks.first?.segments.first?.points.allSatisfy { $0.elevation == nil } == true)
    }

    /// Scenario "Keine gültige Länge".
    @Test func binWithoutValidLength() {
        #expect(throws: GPSLoggerError(.malformed(line: nil), fileName: "a.bin")) {
            try read([UInt8](repeating: 1, count: 13), name: "a.bin", WintecBinFileFormat())
        }
    }

    /// Scenarios "Zwei Tracks und ein Wegpunkt" and "Mehrere Tracks".
    @Test func tk1File() throws {
        let result = try read(WintecTestFile.tk1Fixture(), name: "log.tk1", WintecTK1FileFormat())
        #expect(result.recording.tracks.map(\.name) == ["log (1)", "log (2)"])
        #expect(result.recording.tracks.map(\.pointCount) == [3, 2])
        #expect(result.recording.waypoints.map(\.name) == ["POI 1"])
        #expect(result.recording.tracks[0].segments[0].points.first?.elevation == -2)
        #expect(result.warnings.isEmpty)
    }

    /// TK1 and BIN share the reader: the header decides (as in the source).
    @Test func headerDecides() throws {
        let result = try read(WintecTestFile.tk1Fixture(), name: "log.bin", WintecBinFileFormat())
        #expect(result.recording.trackPointCount == 5)
    }

    @Test func stopsSoonAfterCancellation() async throws {
        let record = WintecTestFile.record16(flags: 0, time: WintecTestFile.base, latitude: 50, longitude: 8, altitude: 1)
        let file = FileInput(name: "big.tes", data: Data((0..<3_300_000).flatMap { _ in record }))
        #expect(file.data.count > 50_000_000)
        let task = Task { try await FileFormats.read([file], format: WintecTESFileFormat()) }
        task.cancel()
        let begin = Date()
        let result = await task.result
        #expect(Date().timeIntervalSince(begin) < 1)
        #expect(throws: CancellationError.self) { try result.get() }
    }

    /// Spec `logger-kit-gpl`, "Wintec-Formate abfragen".
    @Test func catalog() throws {
        let ids = GPLFileFormats.all.map(\.id)
        #expect([.wintecTES, .wbtBin, .wbtTK1].allSatisfy(ids.contains))
        #expect(GPLFileFormats.all.first { $0.id == .wintecTES }?.fileExtensions == ["tes"])
        #expect(GPLFileFormats.all.first { $0.id == .wbtTK1 }?.fileExtensions == ["tk1"])
        #expect(try #require(GPLFileFormats.credits.first).authors.contains("Robert Lipe"))
    }
}

@Suite("Wintec detection")
struct WintecDetectionTests {
    private let catalog = FormatCatalog.standard.adding(GPLFileFormats.all)

    /// Scenario "TK1-Datei".
    @Test func tk1() {
        #expect(catalog.detect(prefix: Data(WintecTestFile.tk1Fixture().prefix(4096)), fileName: "a.tk1")?.id == .wbtTK1)
        #expect(catalog.detect(prefix: Data(WintecTestFile.tk1Fixture().prefix(4096)), fileName: "a.bin")?.id == .wbtTK1)
    }

    /// Scenario "TES-Datei".
    @Test func tes() {
        #expect(catalog.detect(prefix: Data(WintecTestFile.tesFixture()), fileName: "TRK0001.TES")?.id == .wintecTES)
    }

    @Test func bin() {
        #expect(catalog.detect(prefix: Data(WintecTestFile.binFixture()), fileName: "wbt.bin")?.id == .wbtBin)
    }

    /// Scenario "Andere Abbilder" and the other way round.
    @Test func otherDumps() {
        let wintec: [FileFormatID] = [.wintecTES, .wbtBin, .wbtTK1]
        let others = [SkyTraqTestDump.venus().bytes, MTKTestDump.mtkFixture().bytes, MTKTestDump.m241Fixture().bytes]
        for bytes in others {
            let prefix = Data(bytes.prefix(4096))
            for format in GPLFileFormats.all where wintec.contains(format.id) {
                #expect(!format.matches(prefix: prefix), "\(format.id) matches another dump")
            }
        }
        for bytes in [WintecTestFile.tesFixture(), WintecTestFile.binFixture(), WintecTestFile.tk1Fixture()] {
            let prefix = Data(bytes.prefix(4096))
            for format in GPLFileFormats.all where !wintec.contains(format.id) {
                #expect(!format.matches(prefix: prefix), "\(format.id) matches a Wintec file")
            }
        }
        for _ in 0..<50 {
            let random = Data((0..<4096).map { _ in UInt8.random(in: 0...255) })
            for format in GPLFileFormats.all where wintec.contains(format.id) {
                #expect(!format.matches(prefix: random))
            }
        }
    }
}
