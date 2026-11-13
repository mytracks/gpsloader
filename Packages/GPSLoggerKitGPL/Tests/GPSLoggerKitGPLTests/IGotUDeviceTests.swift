// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import GPSLoggerKit
@testable import GPSLoggerKitGPL

/// A simulated i-GotU (spec `igotu-device`): GT-800 over serial or a USB model over HID.
final class IGotUSimulator: @unchecked Sendable {
    private let lock = NSLock()
    let variant: IGotUDevice.Variant
    var flash: [UInt8]  // from address 0; records start at 0x1000
    var count: Int
    var modelByte: UInt8 = 0x14  // GT-200
    var firmware: UInt16 = 0x0215
    var nmeaMode: UInt8 = 1
    var purgedBlocks: [Int] = []
    var deviceErrorOnce = false
    private var pending: [UInt8] = []
    private var writeBusy = 0

    init(variant: IGotUDevice.Variant, records: [[UInt8]]) {
        self.variant = variant
        flash = [UInt8](repeating: 0xFF, count: 0x1000) + records.flatMap { $0 }
        count = records.count
    }

    static func header(_ size: Int) -> [UInt8] { [0x93, UInt8(size >> 8 & 0xFF), UInt8(size & 0xFF)] }

    func respond(_ written: [UInt8]) -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }
        var command = written
        if variant == .hid {
            pending += written
            if pending.count < 16 { return Self.header(0) }  // first chunk acknowledged
            command = pending
            pending = []
        }
        guard command.count == 16, command.reduce(UInt8(0), &+) == 0 else { return [0x93, 0xFF, 0xFE] }
        if deviceErrorOnce { deviceErrorOnce = false; return [0x93, 0xFF, 0xFE] }
        func reply(_ data: [UInt8]) -> [UInt8] { Self.header(data.count) + data }
        switch (command[1], command[2]) {
        case (0x01, _): nmeaMode = command[3]; return reply([])
        case (0x0A, _):
            return reply([0x78, 0x56, 0x34, 0x12, UInt8(firmware >> 8), UInt8(firmware & 0xFF), 0x02, 0, 0, 0])
        case (0x0B, _): return reply([UInt8(count >> 16 & 0x03), UInt8(count >> 8 & 0xFF), UInt8(count & 0xFF)])
        case (0x05, 0x04):
            if command[6] == 0x9F { return reply([0xC2, 0x20, modelByte]) }
            writeBusy = max(0, writeBusy - 1)
            return reply([writeBusy == 0 ? 0x00 : 0x03])  // UnknownWriteCommand2
        case (0x05, 0x07):
            let size = Int(command[3]) << 8 | Int(command[4])
            let position = Int(command[7]) << 16 | Int(command[8]) << 8 | Int(command[9])
            return reply((position..<(position + size)).map { $0 < flash.count ? flash[$0] : 0xFF })
        case (0x06, 0x04): return reply([])
        case (0x06, 0x07):
            let position = Int(command[7]) << 16 | Int(command[8]) << 8 | Int(command[9])
            purgedBlocks.append(position / 0x1000)
            writeBusy = 2
            return reply([])
        case (0x0C, _), (0x08, _): return reply([])
        default: return [0x93, 0xFF, 0xFE]
        }
    }
}

/// A 32-byte record (big endian) as described in docs/legacy-analysis.md (i-GotU).
func igotuRecord(flags: UInt8 = 0, year: Int = 2026, month: Int = 11, day: Int = 2, hour: Int = 12, minute: Int = 0,
                 millisecond: Int = 0, latitude: Double = 50, longitude: Double = 8, elevation: Double = 100,
                 satellites: UInt8 = 7, maximumSV: UInt8 = 9) -> [UInt8] {
    func be32(_ v: Int32) -> [UInt8] { let u = UInt32(bitPattern: v); return [24, 16, 8, 0].map { UInt8(u >> UInt32($0) & 0xFF) } }
    var r = [UInt8](repeating: 0, count: 32)
    r[0] = flags
    r[1] = UInt8(year % 16) << 4 | UInt8(month)
    r[2] = UInt8(day) << 3 | UInt8(hour / 4)
    r[3] = UInt8(hour % 4) << 6 | UInt8(minute)
    r[4] = UInt8(millisecond >> 8); r[5] = UInt8(millisecond & 0xFF)
    r.replaceSubrange(0x0C..<0x10, with: be32(Int32((latitude * 1e7).rounded())))
    r.replaceSubrange(0x10..<0x14, with: be32(Int32((longitude * 1e7).rounded())))
    r.replaceSubrange(0x14..<0x18, with: be32(Int32((elevation * 100).rounded())))
    r[0x1D] = maximumSV << 4 | satellites
    return r
}

private func device(_ simulator: IGotUSimulator) -> SimulatedDevice {
    SimulatedDevice(baudRate: 9600, initialInput: Array("$GPGGA,noise*00\r\n".utf8)) { written, _ in simulator.respond(written) }
}

private func driver(_ variant: IGotUDevice.Variant) -> IGotUDevice {
    var driver = IGotUDevice(variant: variant)
    driver.reference = { skyTraqReference }
    return driver
}

@Suite("i-GotU device")
struct IGotUDeviceTests {
    private static func records() -> [[UInt8]] {
        var records = (0..<150).map { k in
            igotuRecord(flags: k == 0 ? 0x40 : (k == 10 ? 0x04 : 0), minute: k / 60, millisecond: (k % 60) * 1000 + 250,
                        latitude: 50 + Double(k) * 0.0001)
        }
        records[20] = igotuRecord(flags: 0x10)  // invalid navigation data
        records[21] = [0xF1] + [UInt8](repeating: 0x41, count: 31)  // debug text
        records[100] = igotuRecord(flags: 0x40, minute: 40, latitude: 51)  // new track
        return records
    }

    /// Scenarios "GT-800 auslesen" and "USB-Modell auslesen".
    @Test(arguments: [IGotUDevice.Variant.serial, .hid])
    func reads(variant: IGotUDevice.Variant) async throws {
        let simulator = IGotUSimulator(variant: variant, records: Self.records())
        let recording = try await driver(variant).read(device(simulator), DeviceReporter())
        #expect(recording.tracks.map(\.pointCount) == [98, 50])
        #expect(recording.waypoints.map(\.name) == ["POI 1"])
        let first = try #require(recording.tracks.first?.segments.first?.points.first)
        #expect(first.latitude == 50 && first.longitude == 8 && first.elevation == 100)
        #expect(first.time == ISO8601DateFormatter().date(from: "2026-11-02T12:00:00Z").map { $0.addingTimeInterval(0.25) })
        #expect(simulator.nmeaMode == 0)  // back to NMEA mode
    }

    /// Scenario "Jahr modulo 16".
    @Test func yearReconstruction() {
        let r = ByteReader(bytes: igotuRecord(year: 2027))  // 2027 % 16 = 11 > 2026 % 16 = 10 → 2011
        #expect(IGotUDevice.time(r, 0, currentYear: 2026) == ISO8601DateFormatter().date(from: "2011-11-02T12:00:00Z"))
        #expect(IGotUDevice.time(ByteReader(bytes: igotuRecord(year: 2026)), 0, currentYear: 2026)
                == ISO8601DateFormatter().date(from: "2026-11-02T12:00:00Z"))
    }

    /// Scenario "Wenige Satelliten": the GT-800 needs more than 4 satellites, USB models more than 0.
    @Test func satelliteThreshold() {
        let data = igotuRecord(satellites: 3)
        #expect(IGotUDevice.decode(data, count: 1, variant: .serial, reference: skyTraqReference).trackPointCount == 0)
        #expect(IGotUDevice.decode(data, count: 1, variant: .hid, reference: skyTraqReference).trackPointCount == 1)
    }

    /// Scenario "Gerätefehler": a negative response size is retried.
    @Test func deviceErrorIsRetried() async throws {
        let simulator = IGotUSimulator(variant: .serial, records: Self.records())
        simulator.deviceErrorOnce = true
        let recording = try await driver(.serial).read(device(simulator), DeviceReporter())
        #expect(recording.trackPointCount == 148)
    }

    @Test func frameChecksum() {
        let frame = IGotULink.frame([0x93, 0x0B, 0x03, 0x00, 0x1D])
        #expect(frame.count == 16 && frame.reduce(UInt8(0), &+) == 0 && frame[15] == 0x42)
    }

    /// Scenario "Speicher löschen (experimentell)": used blocks are purged from the top down.
    @Test(arguments: [IGotUDevice.Variant.serial, .hid])
    func erase(variant: IGotUDevice.Variant) async throws {
        let simulator = IGotUSimulator(variant: variant, records: Self.records())  // 150 records = 2 blocks
        try await driver(variant).erase(device(simulator), DeviceReporter())
        #expect(simulator.purgedBlocks == [2, 1])
        #expect(driver(variant).eraseSupport == .experimental)
    }

    @Test func eraseUnknownUSBModel() async {
        let simulator = IGotUSimulator(variant: .hid, records: [])
        simulator.modelByte = 0x17  // GT-200e: not supported by igotu2gpx
        await #expect(throws: DeviceProtocolError("Erasing is not supported for this i-GotU model")) {
            try await driver(.hid).erase(device(simulator), DeviceReporter())
        }
    }
}
