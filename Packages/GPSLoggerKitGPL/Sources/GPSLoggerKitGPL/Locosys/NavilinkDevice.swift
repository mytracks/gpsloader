// Ported from GPSBabel navilink.cc (tag gpsbabel_1_7_0), serial download of the format navilink.
// Original: Copyright (C) 2007 Tom Hughes, Copyright (C) 2008 Rodney Lorrimar.
// Licensed under the GNU General Public License, version 2 or (at your option) any later version.
// Translated to Swift and modified for gpsloader by Dirk Stichling, 2026-11-13.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GPSLoggerKit

/// Reads waypoints and the track log of Locosys NaviGPS / GT-11 / GT-31 / BGT-31 devices in NAVILINK mode
/// (spec `navilink-device`).
public struct NavilinkDevice: DeviceProtocol {
    public init() {}

    public static let baudRate = 115_200
    static let timeout: TimeInterval = 8  // SERIAL_TIMEOUT 8000 ms
    static let maxReadTrackpoints = 512

    enum PID {
        static let sync: UInt8 = 0xD6, ack: UInt8 = 0x0C, nak: UInt8 = 0x00, queryInformation: UInt8 = 0x20
        static let data: UInt8 = 0x03, queryWaypoints: UInt8 = 0x28, readTrackpoints: UInt8 = 0x14
    }

    public func read(_ connection: any DeviceConnection, _ reporter: DeviceReporter) async throws -> Recording {
        let link = NavilinkLink(connection: connection)
        reporter.step("Connecting")
        try await link.write(PID.sync)
        _ = try await link.read(PID.ack, length: 0)

        // serial_read_waypoints
        try await link.write(PID.queryInformation)
        let information = ByteReader(bytes: try await link.read(PID.data, length: 32))
        let waypointTotal = Int(information.u16le(0) ?? 0)
        let trackAddress = Int(information.u32le(4) ?? 0)
        let trackTotal = Int(information.u16le(12) ?? 0)
        var waypoints: [Waypoint] = []
        var start = 0
        while start < waypointTotal {
            let count = min(waypointTotal - start, 32)
            try await link.write(PID.queryWaypoints, NavilinkLink.le32(start) + NavilinkLink.le16(count) + [1])
            let bytes = try await link.read(PID.data, length: count * 32)
            for k in 0..<count { waypoints.append(Self.waypoint(ByteReader(bytes: bytes), k * 32)) }
            start += count
            reporter.progress(start, of: waypointTotal + trackTotal, step: "Reading waypoints")
        }

        // serial_read_track
        var points: [TrackPoint] = []
        var address = trackAddress
        var remaining = trackTotal
        while remaining > 0 {
            let count = min(remaining, Self.maxReadTrackpoints)
            try await link.write(PID.readTrackpoints, NavilinkLink.le32(address) + NavilinkLink.le16(count * 32) + [0])
            let bytes = try await link.read(PID.data, length: count * 32)
            try await link.write(PID.ack)
            for k in 0..<count { points.append(Self.trackpoint(ByteReader(bytes: bytes), k * 32)) }
            address += count * 32
            remaining -= count
            reporter.progress(waypointTotal + trackTotal - remaining, of: waypointTotal + trackTotal, step: "Reading track")
        }
        return Recording(tracks: points.isEmpty ? [] : [Track(name: "NaviGPS", segments: [TrackSegment(points: points)])],
                         waypoints: waypoints)
    }

    /// `decode_datetime`: year since 2000, month, day, hour, minute, second (UTC).
    static func time(_ r: ByteReader, _ o: Int) -> Date? {
        Locosys.utc(year: 2000 + Int(r.u8(o) ?? 0), month: Int(r.u8(o + 1) ?? 0), day: Int(r.u8(o + 2) ?? 0),
                    hour: Int(r.u8(o + 3) ?? 0), minute: Int(r.u8(o + 4) ?? 0), second: Double(r.u8(o + 5) ?? 0))
    }

    /// `decode_position`: latitude and longitude in 1e-7 degrees, altitude in feet.
    static func position(_ r: ByteReader, _ o: Int) -> (Double, Double, Double) {
        (Double(Locosys.i32le(r, o)) / 10_000_000, Double(Locosys.i32le(r, o + 4)) / 10_000_000,
         Double(r.u16le(o + 8) ?? 0) * 0.3048)
    }

    /// `decode_trackpoint`.
    static func trackpoint(_ r: ByteReader, _ o: Int) -> TrackPoint {
        let (latitude, longitude, altitude) = position(r, o + 12)
        var quality = PositionQuality()
        quality.course = Double(r.u16le(o + 2) ?? 0)
        quality.speed = Double(r.u8(o + 29) ?? 0) * 2 / 3.6
        return TrackPoint(latitude: latitude, longitude: longitude, elevation: altitude, time: time(r, o + 22),
                          quality: quality)
    }

    /// `decode_waypoint`: name at offset 4 (zero terminated), position, time.
    static func waypoint(_ r: ByteReader, _ o: Int) -> Waypoint {
        let (latitude, longitude, altitude) = position(r, o + 12)
        let nameBytes = (4..<12).compactMap { r.u8(o + $0) }.prefix { $0 != 0 }
        return Waypoint(latitude: latitude, longitude: longitude, elevation: altitude, time: time(r, o + 22),
                        name: String(decoding: nameBytes, as: UTF8.self))
    }
}

/// Packet layer (`write_packet`, `read_packet`).
struct NavilinkLink {
    let connection: any DeviceConnection

    static func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
    static func le32(_ v: Int) -> [UInt8] { (0..<4).map { UInt8(v >> (8 * $0) & 0xFF) } }

    static func packet(_ type: UInt8, _ payload: [UInt8] = []) -> [UInt8] {
        let body = [type] + payload
        let checksum = body.reduce(0) { $0 + Int($1) } & 0x7FFF
        return [0xA0, 0xA2] + le16(body.count) + body + le16(checksum) + [0xB0, 0xB3]
    }

    func write(_ type: UInt8, _ payload: [UInt8] = []) async throws {
        try await connection.write(Self.packet(type, payload))
    }

    /// Reads a packet of `type` and returns `length` payload bytes (fewer if the packet is shorter).
    func read(_ type: UInt8, length: Int) async throws -> [UInt8] {
        let header = try await connection.read(count: 4, timeout: NavilinkDevice.timeout)
        guard header[0] == 0xA0, header[1] == 0xA2 else {
            throw DeviceProtocolError("Bad packet header. Is the device in NAVILINK mode?")
        }
        let size = Int(header[2]) | Int(header[3]) << 8
        guard size > length, size >= 1 else { throw DeviceProtocolError("Packet too short") }
        let data = try await connection.read(count: size, timeout: NavilinkDevice.timeout + Double(size) / 1000)
        guard data[0] == type else {
            throw DeviceProtocolError(String(format: "Bad packet type (expected 0x%02x but got 0x%02x)", type, data[0]))
        }
        let trailer = try await connection.read(count: 4, timeout: NavilinkDevice.timeout)
        let checksum = data.reduce(0) { $0 + Int($1) } & 0x7FFF
        guard Int(trailer[0]) | Int(trailer[1]) << 8 == checksum else { throw DeviceProtocolError("Checksum error") }
        guard trailer[2] == 0xB0, trailer[3] == 0xB3 else { throw DeviceProtocolError("Bad packet trailer") }
        return Array(data.dropFirst().prefix(length))
    }
}
