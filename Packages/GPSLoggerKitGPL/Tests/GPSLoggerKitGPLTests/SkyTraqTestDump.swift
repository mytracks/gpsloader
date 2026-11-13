// Test encoder for SkyTraq dumps: the inverse of the decoder in SkyTraqBinFileFormat.swift.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
@testable import GPSLoggerKitGPL

/// Writes SkyTraq log items and sectors (design D7 of change skytraq-bin-port).
struct SkyTraqTestDump {
    private(set) var sectors: [[UInt8]] = []
    private var current: [UInt8] = []

    /// Middle endian: low 16 bits (big endian) first, then the high 16 bits (big endian).
    static func middleEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF), UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF)]
    }

    static func middleEndian(_ value: Int32) -> [UInt8] {
        middleEndian(UInt32(bitPattern: value))
    }

    /// WGS 84 to ECEF (meters), rounded.
    static func ecef(latitude: Double, longitude: Double, height: Double) -> (Int32, Int32, Int32) {
        let a = 6_378_137.0
        let b = 6_356_752.31424518
        let e2 = (a * a - b * b) / (a * a)
        let phi = latitude * .pi / 180, lambda = longitude * .pi / 180
        let n = a / (1 - e2 * sin(phi) * sin(phi)).squareRoot()
        return (Int32(((n + height) * cos(phi) * cos(lambda)).rounded()),
                Int32(((n + height) * cos(phi) * sin(lambda)).rounded()),
                Int32(((n * (1 - e2) + height) * sin(phi)).rounded()))
    }

    static func typeAndSpeed(_ type: UInt8, _ speed: Int) -> [UInt8] {
        [type << 4 | UInt8(speed >> 8 & 0x0F), UInt8(speed & 0xFF)]
    }

    static func full(week: Int, second: Int, x: Int32, y: Int32, z: Int32, speed: Int = 0, poi: Bool = false) -> [UInt8] {
        typeAndSpeed(poi ? 0x6 : 0x4, speed) + middleEndian(UInt32(second) << 12 | UInt32(week & 0x3FF))
            + middleEndian(x) + middleEndian(y) + middleEndian(z)
    }

    static func full(week: Int, second: Int, latitude: Double, longitude: Double, height: Double, speed: Int = 0,
                     poi: Bool = false) -> [UInt8] {
        let (x, y, z) = ecef(latitude: latitude, longitude: longitude, height: height)
        return full(week: week, second: second, x: x, y: y, z: z, speed: speed, poi: poi)
    }

    /// The 10-bit encoding of a delta in -512...511 (inverse of `511 - value`).
    static func delta10(_ d: Int) -> Int {
        precondition((-512...511).contains(d))
        return d >= 0 ? d : 511 - d
    }

    static func compact(dt: Int, dx: Int, dy: Int, dz: Int, speed: Int = 0) -> [UInt8] {
        let vx = delta10(dx), vy = delta10(dy), vz = delta10(dz)
        let p0 = UInt8(vx >> 2 & 0xFF)
        let p1 = UInt8((vx & 0x03) << 6 | (vy & 0x3F))
        let p2 = UInt8((vy >> 6 & 0x0F) << 4 | (vz >> 8 & 0x03))
        let p3 = UInt8(vz & 0xFF)
        return typeAndSpeed(0x8, speed) + [UInt8(dt >> 8 & 0xFF), UInt8(dt & 0xFF), p0, p1, p2, p3]
    }

    static func multiHz(week: Int, millisecond: Int, latitude: Double, longitude: Double, height: Double,
                        speed: Int = 0, poi: Bool = false) -> [UInt8] {
        [(poi ? 0xC : 0x2) << 4 | UInt8(week >> 8 & 0x03), UInt8(week & 0xFF), UInt8(speed >> 8 & 0xFF), UInt8(speed & 0xFF)]
            + middleEndian(UInt32(millisecond))
            + middleEndian(Int32((latitude * 1_048_576).rounded()))
            + middleEndian(Int32((longitude * 1_048_576).rounded()))
            + middleEndian(Int32((height * 128).rounded()))
    }

    mutating func append(_ item: [UInt8]) {
        current += item
    }

    /// Ends the current sector, padding it with 0xFF to 4096 bytes.
    mutating func endSector() {
        precondition(current.count <= SkyTraqDump.sectorSize)
        sectors.append(current + [UInt8](repeating: 0xFF, count: SkyTraqDump.sectorSize - current.count))
        current = []
    }

    var bytes: [UInt8] { sectors.flatMap { $0 } }
    var data: Data { Data(bytes) }

    /// The fixture `venus.bin`: a full first sector, a partly used second one, then a sector that must
    /// not be read because the second one ended early.
    static func venus() -> SkyTraqTestDump {
        var dump = SkyTraqTestDump()
        dump.append(full(week: 380, second: 302_400, latitude: 50.0, longitude: 8.0, height: 100, speed: 18))
        for k in 0..<508 {
            dump.append(compact(dt: 1, dx: 3, dy: k % 2 == 0 ? -2 : -1, dz: 1, speed: 18 + k % 3))
        }
        dump.endSector()
        dump.append(full(week: 380, second: 303_000, latitude: 50.01, longitude: 8.02, height: 150.5, speed: 36))
        dump.append(compact(dt: 5, dx: 3, dy: -2, dz: 1, speed: 36))
        dump.append(full(week: 380, second: 303_010, latitude: 50.011, longitude: 8.021, height: 151, speed: 0, poi: true))
        dump.append(compact(dt: 2, dx: -512, dy: 511, dz: -1, speed: 40))
        dump.append(multiHz(week: 380, millisecond: 303_020_000, latitude: 50.02, longitude: 8.03, height: 160.25, speed: 72))
        dump.append(multiHz(week: 380, millisecond: 303_020_100, latitude: 50.02001, longitude: 8.03001, height: 160.5, speed: 72))
        dump.append(multiHz(week: 380, millisecond: 303_020_200, latitude: 50.02002, longitude: 8.03002, height: 160.75,
                            speed: 72, poi: true))
        dump.endSector()
        dump.append(full(week: 380, second: 400_000, latitude: 10, longitude: 10, height: 0))
        dump.endSector()
        return dump
    }
}
