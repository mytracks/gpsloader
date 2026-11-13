// Ported from GPSBabel itracku.cc (tag gpsbabel_1_7_0), serial download of the format itracku.
// Original: Copyright (C) 2008 Andreas Grimme; Copyright (C) 2005 Robert Lipe.
// Licensed under the GNU General Public License, version 2 or (at your option) any later version.
// Translated to Swift and modified for gpsloader by Dirk Stichling, 2026-11-13.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GPSLoggerKit

/// Reads the memory of the XAiOX iTrackU (Bluetooth GPS receiver with logger) over a serial connection
/// (spec `itracku-device`). The records become one track.
public struct ITrackUDevice: DeviceProtocol {
    public init() {}

    /// `gbser_init` opens the port with 4800 baud; the source does not change it.
    public static let baudRate = 4800
    /// `timeout` and the line timeout of `itracku_device_read_string`.
    static let timeout: TimeInterval = 1
    static let greeting = "WP GPS+BT"
    /// `read_update_data_command`.
    static let readCommand: [UInt8] = [0x60, 0xB5, 0, 0, 0, 0, 0]
    /// `update_end_marker`; the source expects one more byte (its terminating zero) after it.
    static let endMarker = Array("WP Update Over".utf8)
    static let recordLength = 16
    static let maxMemory = 64 << 20
    static let trackName = "iTrackU"

    public func read(_ connection: any DeviceConnection, _ reporter: DeviceReporter) async throws -> Recording {
        reporter.step("Connecting")
        try await Self.initDevice(connection)

        // `itracku_device_dump_waypts`
        reporter.step("Reading memory")
        try await connection.write(Self.readCommand)
        let data = try await connection.readUntil(Self.endMarker, maxLength: Self.maxMemory, timeout: Self.timeout)
        _ = try? await connection.read(count: 1, timeout: 0.2)  // the byte after the marker
        let points = Self.decode(data)
        return Recording(tracks: points.isEmpty ? [] : [Track(name: Self.trackName, segments: [TrackSegment(points: points)])])
    }

    /// `init_device`: `WP AP-Exit`, flush, `W'P Camera Detect`, then the zero-terminated greeting.
    static func initDevice(_ connection: any DeviceConnection) async throws {
        try await connection.write(string("WP AP-Exit"))
        await connection.discardInput()
        try await connection.write(string("W'P Camera Detect"))
        let answer: [UInt8]
        do {
            answer = try await connection.readUntil([0x00], maxLength: 1024, timeout: timeout)
        } catch {
            if error is CancellationError || Task.isCancelled { throw error }
            throw DeviceProtocolError("No iTrackU found on this port")
        }
        // The source compares the whole line; NMEA output that arrived before the greeting is accepted here.
        guard String(decoding: answer, as: UTF8.self).hasSuffix(greeting) else {
            throw DeviceProtocolError("No iTrackU found on this port")
        }
    }

    /// `itracku_device_write_string`: the text with its terminating zero.
    static func string(_ text: String) -> [UInt8] { Array(text.utf8) + [0] }

    /// All complete 16-byte records; empty records (longitude 0xFFFFFFFF) are skipped.
    static func decode(_ data: [UInt8]) -> [TrackPoint] {
        let reader = ByteReader(bytes: data)
        return stride(from: 0, to: data.count - recordLength + 1, by: recordLength).compactMap { record(reader, $0) }
    }

    /// `itracku_is_valid_data_record` and `to_waypoint`.
    static func record(_ r: ByteReader, _ o: Int) -> TrackPoint? {
        guard let longitude = r.u32le(o), longitude != 0xFFFF_FFFF, let latitude = r.u32le(o + 4),
              let time = r.u32le(o + 8), let altitude = r.u16le(o + 12), let speed = r.u8(o + 14) else { return nil }
        var quality = PositionQuality()
        quality.speed = Double(speed) * 1852 / 3600  // KNOTS_TO_MPS
        return TrackPoint(latitude: degrees(latitude), longitude: degrees(longitude), elevation: Double(altitude),
                          time: self.time(time), quality: quality)
    }

    /// `deg_min_to_deg`: `ddd` · 10⁶ + minutes · 10⁴; values above 0x80000000 are negative.
    static func degrees(_ value: UInt32) -> Double {
        var x = value
        var sign = 1.0
        if x > 0x8000_0000 {
            sign = -1
            x -= 0x8000_0000
        }
        let d = x / 1_000_000
        return sign * (Double(d) + Double(x - d * 1_000_000) / 600_000)
    }

    /// `decode_itracku_time`: seconds, minutes, hours, day, month and year since 2000 in 6/6/5/5/4/6 bits (UTC).
    static func time(_ value: UInt32) -> Date? {
        let v = Int(value)
        return Locosys.utc(year: 2000 + (v >> 26 & 63), month: v >> 22 & 15, day: v >> 17 & 31,
                           hour: v >> 12 & 31, minute: v >> 6 & 63, second: Double(v & 63))
    }
}
