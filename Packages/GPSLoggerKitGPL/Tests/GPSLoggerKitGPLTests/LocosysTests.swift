// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import GPSLoggerKit
@testable import GPSLoggerKitGPL

/// Test encoder for SBP and SBN files (design D7 of change locosys-file-port).
enum LocosysTestFile {
    struct Fix {
        var year = 2026, month = 11, day = 2, hour = 12, minute = 0, second = 0, millisecond = 0
        var latitude = 50.0, longitude = 8.0, altitude = 100.0
        var speed = 2.5, course = 90.0  // m/s, degrees
        var satellites: UInt8 = 7, hdop = 1.0
        var validity: UInt16 = 0, mode: UInt8 = 0x04
    }

    static func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
    static func le32(_ v: Int32) -> [UInt8] { let u = UInt32(bitPattern: v); return (0..<4).map { UInt8(u >> (8 * UInt32($0)) & 0xFF) } }
    static func be16(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
    static func be32(_ v: Int32) -> [UInt8] { let u = UInt32(bitPattern: v); return (0..<4).reversed().map { UInt8(u >> (8 * UInt32($0)) & 0xFF) } }

    static func sbpHeader(deviceInfo: String = "GT-31,12345678,1,1.6") -> [UInt8] {
        let info = Array(deviceInfo.utf8)
        var header = le16(7 + info.count) + [0xA0, 0xA2] + be16(info.count + 1) + [0xFD] + info
        header += [UInt8](repeating: 0xFF, count: 64 - header.count)
        return header
    }

    static func packedTime(_ f: Fix) -> UInt32 {
        UInt32((f.year - 2000) * 12 + f.month) << 22 | UInt32(f.day) << 17 | UInt32(f.hour) << 12 | UInt32(f.minute) << 6
            | UInt32(f.second)
    }

    static func sbpRecord(_ f: Fix) -> [UInt8] {
        var r: [UInt8] = [UInt8((f.hdop / 0.2).rounded()), f.satellites] + le16(f.millisecond)
        r += le32(Int32(bitPattern: packedTime(f))) + [0, 0, 0, 0]
        r += le32(Int32((f.latitude * 1e7).rounded())) + le32(Int32((f.longitude * 1e7).rounded()))
        r += le32(Int32((f.altitude * 100).rounded()))
        r += le16(Int((f.speed * 100).rounded())) + le16(Int((f.course * 100).rounded())) + [0, 0, 0, 0]
        return r
    }

    static func sbnPacket(_ data: [UInt8], corrupt: Bool = false) -> [UInt8] {
        let sum = data.reduce(0) { $0 + Int($1) } & 0x7FFF
        return [0xA0, 0xA2] + be16(data.count) + data + be16(corrupt ? sum ^ 0x55 : sum) + [0xB0, 0xB3]
    }

    static func sbnInformation() -> [UInt8] {
        sbnPacket([253] + Array("GT-31,12345678,1,1.6".utf8))
    }

    static func sbnNavigation(_ f: Fix) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: 91)
        func put(_ bytes: [UInt8], at offset: Int) { p.replaceSubrange(offset..<(offset + bytes.count), with: bytes) }
        put(be16(Int(f.validity)), at: 0)
        p[3] = f.mode
        put(be16(f.year) + [UInt8(f.month), UInt8(f.day), UInt8(f.hour), UInt8(f.minute)] + be16(f.second * 1000 + f.millisecond), at: 10)
        put(be32(Int32((f.latitude * 1e7).rounded())) + be32(Int32((f.longitude * 1e7).rounded())), at: 22)
        put(be32(Int32((f.altitude * 100).rounded())), at: 34)
        put(be16(Int((f.speed * 100).rounded())) + be16(Int((f.course * 100).rounded())), at: 39)
        p[87] = f.satellites
        p[88] = UInt8((f.hdop / 0.2).rounded())
        return sbnPacket([41] + p)
    }

    static func sbpFixture() -> [UInt8] {
        sbpHeader() + (0..<5).flatMap { k in
            sbpRecord(Fix(second: k, millisecond: k * 100, latitude: 50.03 + Double(k) * 0.0001, longitude: 8.03,
                          altitude: 150.25 + Double(k), speed: Double(k), course: Double(k * 10), satellites: UInt8(6 + k)))
        }
    }

    static func sbnFixture() -> [UInt8] {
        var bytes = sbnInformation()
        for k in 0..<5 {
            bytes += sbnNavigation(Fix(minute: 30, second: k, millisecond: 500, latitude: 50.04 + Double(k) * 0.0001,
                                       longitude: 8.04, altitude: 160 + Double(k), speed: 1.5, course: 180,
                                       mode: k == 4 ? 0x84 : 0x04))
            if k == 2 { bytes += sbnPacket([13, 3, 1, 2, 3]) }
        }
        return bytes
    }
}

private func read(_ bytes: [UInt8], name: String, _ format: any FileFormat) throws -> ImportResult {
    try FileFormats.readSynchronously([FileInput(name: name, data: Data(bytes))], format: format,
                                      options: ImportOptions(referenceDate: skyTraqReference))
}

private func points(_ result: ImportResult) -> [TrackPoint] {
    result.recording.tracks.flatMap { $0.segments.flatMap(\.points) }
}

private func date(_ text: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)!
}

private typealias Fix = LocosysTestFile.Fix

@Suite("Locosys files")
struct LocosysTests {
    /// Scenario "Zu kurze Datei".
    @Test func shortSBP() {
        #expect(throws: GPSLoggerError(.malformed(line: nil), fileName: "a.sbp")) {
            try read([UInt8](repeating: 0xFF, count: 40), name: "a.sbp", SBPFileFormat())
        }
    }

    /// Scenario "Datensatz eines GT-31".
    @Test func sbpRecord() throws {
        let bytes = LocosysTestFile.sbpHeader()
            + LocosysTestFile.sbpRecord(Fix(millisecond: 250, altitude: 123.45, speed: 2.5, course: 90, hdop: 1.0))
        let result = try read(bytes, name: "track.sbp", SBPFileFormat())
        let p = try #require(points(result).first)
        #expect(p.time == date("2026-11-02T12:00:00.250Z"))
        #expect(p.latitude == 50 && p.longitude == 8 && p.elevation == 123.45)
        #expect(p.quality.speed == 2.5 && p.quality.course == 90 && p.quality.satellites == 7 && p.quality.hdop == 1)
        #expect(result.recording.tracks.map(\.name) == ["track"])
        #expect(result.warnings.isEmpty)
    }

    /// Scenario "Dezember".
    @Test func december() {
        let value = UInt32(26 * 12 + 12) << 22 | UInt32(24) << 17
        #expect(SBPFileFormat.time(value, milliseconds: 0) == date("2026-12-24T00:00:00Z"))
        let january = UInt32(26 * 12 + 1) << 22 | UInt32(1) << 17
        #expect(SBPFileFormat.time(january, milliseconds: 0) == date("2026-01-01T00:00:00Z"))
    }

    @Test func truncatedSBP() throws {
        let result = try read(Array(LocosysTestFile.sbpFixture().dropLast(10)), name: "a.sbp", SBPFileFormat())
        #expect(points(result).count == 4)
        #expect(result.warnings.map(\.kind) == [.truncatedFile])
    }

    /// Scenario "Keine SBN-Datei".
    @Test func sbnWithoutInformation() {
        #expect(throws: GPSLoggerError(.malformed(line: nil), fileName: "a.sbn")) {
            try read(LocosysTestFile.sbnNavigation(Fix()), name: "a.sbn", SBNFileFormat())
        }
    }

    /// Scenario "Navigationspaket".
    @Test func sbnNavigation() throws {
        let bytes = LocosysTestFile.sbnInformation()
            + LocosysTestFile.sbnNavigation(Fix(second: 1, millisecond: 500, altitude: 100))
        let result = try read(bytes, name: "log.sbn", SBNFileFormat())
        let p = try #require(points(result).first)
        #expect(p.time == date("2026-11-02T12:00:01.500Z"))
        #expect(p.latitude == 50 && p.longitude == 8 && p.elevation == 100)
        #expect(p.quality.speed == 2.5 && p.quality.course == 90 && p.quality.satellites == 7 && p.quality.hdop == 1)
        #expect(p.quality.fix == .threeD)
        #expect(result.recording.tracks.map(\.name) == ["log"])
    }

    /// Scenarios "Gültiger 3D-Fix mit DGPS" and "Ungültige Lösung".
    @Test func sbnFixTypes() {
        #expect(SBNFileFormat.fix(validity: 0, mode: 0x84) == .dgps)
        #expect(SBNFileFormat.fix(validity: 0, mode: 0x83) == .twoD)
        #expect(SBNFileFormat.fix(validity: 0, mode: 0x06) == .threeD)
        #expect(SBNFileFormat.fix(validity: 0, mode: 0x07) == FixType.none)
        #expect(SBNFileFormat.fix(validity: 1, mode: 0x04) == FixType.none)
    }

    /// Scenario "Falsche Prüfsumme".
    @Test func sbnWrongChecksum() throws {
        var bytes = LocosysTestFile.sbnInformation() + LocosysTestFile.sbnNavigation(Fix(second: 0))
        let bad = LocosysTestFile.sbnNavigation(Fix(second: 1))
        bytes += Array(bad.dropLast(4)) + [bad[bad.count - 4] ^ 0x01, bad[bad.count - 3], 0xB0, 0xB3]
        bytes += LocosysTestFile.sbnNavigation(Fix(second: 2))
        let result = try read(bytes, name: "a.sbn", SBNFileFormat())
        #expect(points(result).count == 2)
        #expect(result.warnings.map(\.kind) == [.checksumMismatch])
    }

    @Test func sbnBrokenFrame() throws {
        let bytes = LocosysTestFile.sbnInformation() + LocosysTestFile.sbnNavigation(Fix()) + [0x12, 0x34, 0x56]
        let result = try read(bytes, name: "a.sbn", SBNFileFormat())
        #expect(points(result).count == 1)
        #expect(result.warnings.map(\.kind) == [.truncatedFile])
    }

    @Test func stopsSoonAfterCancellation() async throws {
        let record = LocosysTestFile.sbpRecord(Fix())
        let file = FileInput(name: "big.sbp", data: Data(LocosysTestFile.sbpHeader() + (0..<1_700_000).flatMap { _ in record }))
        #expect(file.data.count > 50_000_000)
        let task = Task { try await FileFormats.read([file], format: SBPFileFormat()) }
        task.cancel()
        let begin = Date()
        let result = await task.result
        #expect(Date().timeIntervalSince(begin) < 1)
        #expect(throws: CancellationError.self) { try result.get() }
    }

    /// Spec `logger-kit-gpl`, "Locosys-Formate abfragen".
    @Test func catalog() throws {
        let ids = GPLFileFormats.all.map(\.id)
        #expect(ids.contains(.sbp) && ids.contains(.sbn))
        #expect(try #require(GPLFileFormats.credits.first).authors.contains("Rodney Lorrimar"))
    }
}

@Suite("Locosys detection")
struct LocosysDetectionTests {
    private let catalog = FormatCatalog.standard.adding(GPLFileFormats.all)

    /// Scenarios "SBN-Datei" and "SBP-Datei".
    @Test func detected() {
        #expect(catalog.detect(prefix: Data(LocosysTestFile.sbnFixture()), fileName: "a.sbn")?.id == .sbn)
        #expect(catalog.detect(prefix: Data(LocosysTestFile.sbpFixture()), fileName: "a.sbp")?.id == .sbp)
        #expect(catalog.detect(prefix: Data(LocosysTestFile.sbpFixture()), fileName: "a.dat")?.id == .sbp)
        var noMarker = LocosysTestFile.sbpFixture()
        noMarker[6] = 0x00
        #expect(SBPFileFormat().matches(prefix: Data(noMarker)))
    }

    /// Scenario "Andere Dateien" and the other way round.
    @Test func otherFiles() {
        let others = [SkyTraqTestDump.venus().bytes, MTKTestDump.mtkFixture().bytes, MTKTestDump.m241Fixture().bytes,
                      WintecTestFile.tesFixture(), WintecTestFile.binFixture(), WintecTestFile.tk1Fixture()]
        for bytes in others {
            let prefix = Data(bytes.prefix(4096))
            #expect(!SBPFileFormat().matches(prefix: prefix) && !SBNFileFormat().matches(prefix: prefix))
        }
        for bytes in [LocosysTestFile.sbpFixture(), LocosysTestFile.sbnFixture()] {
            for format in GPLFileFormats.all where format.id != .sbp && format.id != .sbn {
                #expect(!format.matches(prefix: Data(bytes)), "\(format.id) matches a Locosys file")
            }
        }
        var generator = SplitMix64(seed: 0x6770_736C_6F61_6465)  // deterministic: random blocks made this test flaky
        for _ in 0..<50 {
            let random = Data((0..<4096).map { _ in UInt8.random(in: 0...255, using: &generator) })
            #expect(!SBPFileFormat().matches(prefix: random) && !SBNFileFormat().matches(prefix: random))
        }
    }
}

/// Small seeded generator for reproducible "random" test data.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
