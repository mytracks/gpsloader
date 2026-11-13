// Test encoder for MTK dumps: the inverse of the decoder in MTKBinFileFormat.swift.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
@testable import GPSLoggerKitGPL

/// Writes MTK/Holux headers, info blocks, identification strings and records (design D7 of change mtk-bin-port).
struct MTKTestDump {
    enum Bit {
        static let utc = 1 << 0, valid = 1 << 1, latitude = 1 << 2, longitude = 1 << 3, height = 1 << 4
        static let speed = 1 << 5, heading = 1 << 6, dsta = 1 << 7, dage = 1 << 8, pdop = 1 << 9, hdop = 1 << 10
        static let vdop = 1 << 11, nsat = 1 << 12, sid = 1 << 13, elevation = 1 << 14, azimuth = 1 << 15
        static let snr = 1 << 16, rcr = 1 << 17, millisecond = 1 << 18, distance = 1 << 19
        static let basic = utc | valid | latitude | longitude | height | speed
    }

    struct Record {
        var time: UInt32
        var valid: UInt16 = 0x0002
        var latitude = 50.0, longitude = 8.0, height = 100.0
        var speed = 36.0  // km/h (GR245: the value is written as cm/s of speed / 3.6 * 100)
        var heading = 45.0
        var pdop = 1.5, hdop = 1.0, vdop = 1.2
        var satellitesInView: UInt8 = 9, satellitesUsed: UInt8 = 7
        var satellites: [(id: UInt8, used: UInt8)] = []
        var rcr: UInt16 = 0x0001
        var millisecond: UInt16 = 0
        var distance = 0.0
    }

    enum Device { case mtk, holux, gr245 }

    private(set) var bytes: [UInt8] = []
    var device: Device
    var mask: Int

    init(mask: Int, device: Device = .mtk, policy: UInt16 = 0x0106) {
        self.mask = mask
        self.device = device
        bytes = header(mask: mask, policy: policy)
        bytes += [UInt8](repeating: 0xFF, count: 0x200 - bytes.count)
    }

    func header(mask: Int, policy: UInt16) -> [UInt8] {
        Self.le16(0xFFFF) + Self.le32(UInt32(mask)) + Self.le16(policy) + Self.le32(50) + Self.le32(0) + Self.le32(0)
    }

    static func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
    static func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8(v >> (8 * UInt32($0)) & 0xFF) } }
    static func le64(_ v: UInt64) -> [UInt8] { (0..<8).map { UInt8(v >> (8 * UInt64($0)) & 0xFF) } }
    static func f32(_ v: Double) -> [UInt8] { le32(Float(v).bitPattern) }
    static func f64(_ v: Double) -> [UInt8] { le64(v.bitPattern) }
    /// The upper three bytes of a little endian float.
    static func f24(_ v: Double) -> [UInt8] { Array(f32(v).dropFirst()) }

    mutating func info(_ type: UInt8, _ value: UInt32) {
        bytes += [UInt8](repeating: 0xAA, count: 7) + [type] + Self.le32(value) + [0xBB, 0xBB, 0xBB, 0xBB]
    }

    mutating func holux(_ text: String, spaces: Bool = false) {
        precondition(text.utf8.count == 16)
        bytes += Array(text.utf8) + (spaces ? Array("    ".utf8) : [])
    }

    func fields(_ r: Record) -> [UInt8] {
        var out: [UInt8] = []
        func has(_ bit: Int) -> Bool { mask & bit != 0 }
        if has(Bit.utc) { out += Self.le32(r.time) }
        if has(Bit.valid) { out += Self.le16(r.valid) }
        if has(Bit.latitude) { out += device == .mtk ? Self.f64(r.latitude) : Self.f32(r.latitude) }
        if has(Bit.longitude) { out += device == .mtk ? Self.f64(r.longitude) : Self.f32(r.longitude) }
        switch device {
        case .mtk:
            if has(Bit.height) { out += Self.f32(r.height) }
            if has(Bit.speed) { out += Self.f32(r.speed) }
        case .holux:
            if has(Bit.height) { out += Self.f24(r.height) }
            if has(Bit.speed) { out += Self.f32(r.speed) }
        case .gr245:
            if has(Bit.height) { out += Self.le32(UInt32((r.speed / 3.6 * 100).rounded())) }
            if has(Bit.speed) { out += Self.f24(r.height) }
        }
        if has(Bit.heading) { out += Self.f32(r.heading) }
        if has(Bit.dsta) { out += Self.le16(0) }
        if has(Bit.dage) { out += Self.f32(0) }
        if has(Bit.pdop) { out += Self.le16(UInt16((r.pdop * 100).rounded())) }
        if has(Bit.hdop) { out += Self.le16(UInt16((r.hdop * 100).rounded())) }
        if has(Bit.vdop) { out += Self.le16(UInt16((r.vdop * 100).rounded())) }
        if has(Bit.nsat) { out += [r.satellitesInView, r.satellitesUsed] }
        if has(Bit.sid) {
            let count = UInt16(r.satellites.count)
            let blocks = r.satellites.isEmpty ? [(id: UInt8(0), used: UInt8(0))] : r.satellites
            for sat in blocks {
                out += [sat.id, sat.used] + Self.le16(count)
                if count > 0 {
                    if has(Bit.elevation) { out += Self.le16(30) }
                    if has(Bit.azimuth) { out += Self.le16(180) }
                    if has(Bit.snr) { out += Self.le16(40) }
                }
            }
        }
        if has(Bit.rcr) { out += Self.le16(r.rcr) }
        if has(Bit.millisecond) { out += Self.le16(r.millisecond) }
        if has(Bit.distance) { out += Self.f64(r.distance) }
        return out
    }

    mutating func record(_ r: Record, corruptChecksum: Bool = false, star: Bool = true) {
        let body = fields(r)
        var crc = body.reduce(UInt8(0), ^)
        if corruptChecksum { crc ^= 0x5A }
        bytes += body
        if device == .mtk { bytes += star ? [0x2A] : [] }
        bytes += [crc]
    }

    /// Pads the current block with 0xFF and starts the next one (header copy, data from 0x200).
    mutating func endBlock(policy: UInt16 = 0x0106) {
        let next = (bytes.count / 0x10000 + 1) * 0x10000
        bytes += [UInt8](repeating: 0xFF, count: next - bytes.count)
        bytes += header(mask: mask, policy: policy)
        bytes += [UInt8](repeating: 0xFF, count: 0x200 - 20)
    }

    /// Pads to the end of the current block (end of the dump).
    mutating func finish() {
        let next = (bytes.count / 0x10000 + 1) * 0x10000
        bytes += [UInt8](repeating: 0xFF, count: next - bytes.count)
    }

    var data: Data { Data(bytes) }

    /// 2026-11-02T12:00:00Z.
    static let start: UInt32 = 1_793_620_800

    /// Fixture `mtk.bin`: two blocks, two tracks (logger switched on twice), a button press, milliseconds
    /// and satellite data.
    static func mtkFixture() -> MTKTestDump {
        let mask = Bit.basic | Bit.heading | Bit.pdop | Bit.hdop | Bit.vdop | Bit.nsat | Bit.sid | Bit.elevation
            | Bit.azimuth | Bit.snr | Bit.rcr | Bit.millisecond
        var dump = MTKTestDump(mask: mask)
        dump.info(0x07, 0x0106)
        let sats: [(id: UInt8, used: UInt8)] = [(3, 1), (7, 1), (19, 0)]
        for k in 0..<4 {
            dump.record(Record(time: start + UInt32(k), latitude: 50 + Double(k) * 0.0001, longitude: 8 + Double(k) * 0.0002,
                               height: 100 + Double(k), speed: 36, heading: 90, satellites: sats,
                               rcr: k == 2 ? 0x0009 : 0x0001, millisecond: UInt16(k * 250)))
        }
        dump.endBlock()
        dump.info(0x07, 0x0106)
        for k in 0..<3 {
            dump.record(Record(time: start + 3600 + UInt32(k), latitude: 50.01 + Double(k) * 0.0001, longitude: 8.01,
                               height: -3.5, speed: 0, heading: 0, satellites: [], millisecond: 0))
        }
        dump.finish()
        return dump
    }

    /// Fixture `m241.bin`: Holux M-241 with identification string and a waypoint.
    static func m241Fixture() -> MTKTestDump {
        var dump = MTKTestDump(mask: Bit.basic, device: .holux)
        dump.holux("HOLUXGR241LOGGER", spaces: true)
        for k in 0..<3 {
            dump.record(Record(time: start + 7200 + UInt32(k) * 5, latitude: 50.02 + Double(k) * 0.0001, longitude: 8.02,
                               height: 200 + Double(k), speed: 18))
        }
        dump.holux("HOLUXGR241WAYPNT", spaces: true)
        dump.record(Record(time: start + 7300, latitude: 50.021, longitude: 8.021, height: 210, speed: 0))
        dump.finish()
        return dump
    }
}
