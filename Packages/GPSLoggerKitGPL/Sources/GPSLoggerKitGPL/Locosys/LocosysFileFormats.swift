// Ported from GPSBabel (tag gpsbabel_1_7_0):
//   sbp.cc and sbn.cc: Copyright (C) 2008 Rodney Lorrimar, Copyright (C) 2005 Robert Lipe.
//   navilink.cc (log point decoding, packet checksum): Copyright (C) 2007 Tom Hughes, Copyright (C) 2008 Rodney Lorrimar.
//   navilink.h (SBP_RECORD_LEN): Copyright (C) 2008 Rodney Lorrimar, Copyright (C) 2005 Robert Lipe.
// All licensed under the GNU General Public License, version 2 or (at your option) any later version.
// Translated to Swift and modified for gpsloader by Dirk Stichling, 2026-11-13.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GPSLoggerKit

extension FileFormatID {
    public static let sbp: FileFormatID = "sbp"
    public static let sbn: FileFormatID = "sbn"
}

enum Locosys {
    /// `navilink_checksum_packet`: sum of the bytes, 15 bits.
    static func checksum(_ reader: ByteReader, from: Int, count: Int) -> UInt16 {
        var sum = 0
        for k in 0..<count { sum += Int(reader.u8(from + k) ?? 0) }
        return UInt16(sum & 0x7FFF)
    }

    static func i32be(_ r: ByteReader, _ o: Int) -> Int32 { Int32(bitPattern: r.u32be(o) ?? 0) }
    static func i32le(_ r: ByteReader, _ o: Int) -> Int32 { Int32(bitPattern: r.u32le(o) ?? 0) }

    static func utc(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Double) -> Date? {
        guard (1...12).contains(month), day >= 1, day <= WintecTime.daysInMonth(year: year, month: month), hour < 24,
              minute < 60, second >= 0, second < 61 else { return nil }
        let days = WintecTime.daysSince1970(year: year, month: month, day: day)
        return Date(timeIntervalSince1970: Double(days * 86_400 + hour * 3600 + minute * 60) + second)
    }

    static func track(_ points: [TrackPoint], fileName: String) -> [Track] {
        points.isEmpty ? [] : [Track(name: trackName(ofFile: fileName), segments: [TrackSegment(points: points)])]
    }
}

// MARK: - SBP

/// Datalogger files of Locosys GT-11/BGT-11/GT-31/BGT-31 (`sbp.cc`, `navilink_decode_logpoint`), spec `locosys-import`.
public struct SBPFileFormat: FileFormat {
    static let headerLength = 64
    static let recordLength = 32  // SBP_RECORD_LEN

    public init() {}

    public var id: FileFormatID { .sbp }
    public var displayName: String { L10n.string("format.sbp") }
    public var fileExtensions: [String] { ["sbp"] }

    /// `decode_sbp_datetime_packed`: sec 0-5, min 6-11, hour 12-16, day 17-21, year*12+month 22-31.
    static func time(_ value: UInt32, milliseconds: Int) -> Date? {
        var month = Int(value >> 22) % 12
        var year = 2000 + Int(value >> 22) / 12
        if month == 0 {  // tm_mon = -1 in the source, normalized to December of the previous year
            month = 12
            year -= 1
        }
        return Locosys.utc(year: year, month: month, day: Int(value >> 17 & 0x1F), hour: Int(value >> 12 & 0x1F),
                           minute: Int(value >> 6 & 0x3F), second: Double(value & 0x3F) + Double(milliseconds) / 1000)
    }

    /// `navilink_decode_logpoint`.
    static func point(_ r: ByteReader, _ o: Int) -> TrackPoint? {
        guard let time = time(r.u32le(o + 4) ?? 0, milliseconds: Int(r.u16le(o + 2) ?? 0) % 1000) else { return nil }
        var quality = PositionQuality()
        quality.hdop = Double(r.u8(o) ?? 0) * 0.2
        quality.satellites = Int(r.u8(o + 1) ?? 0)
        quality.speed = Double(r.u16le(o + 24) ?? 0) * 0.01
        quality.course = Double(r.u16le(o + 26) ?? 0) * 0.01
        return TrackPoint(latitude: Double(Locosys.i32le(r, o + 12)) / 10_000_000,
                          longitude: Double(Locosys.i32le(r, o + 16)) / 10_000_000,
                          elevation: Double(Locosys.i32le(r, o + 20)) / 100, time: time, quality: quality)
    }

    public func matches(prefix: Data) -> Bool {
        let r = ByteReader(prefix)
        guard r.count >= Self.headerLength + Self.recordLength else { return false }
        var text: [UInt8] = []
        var k = 7
        while k < Self.headerLength, let byte = r.u8(k), byte != 0xFF, byte != 0 {
            text.append(byte)
            k += 1
        }
        let deviceInfo = !text.isEmpty && text.allSatisfy { (0x20...0x7E).contains($0) } && text.contains(0x2C)
        // The first record has a time from 2004 on (1072915200 = 2004-01-01T00:00:00Z).
        guard r.u8(6) == 0xFD || deviceInfo, let point = Self.point(r, Self.headerLength),
              let time = point.time, time.timeIntervalSince1970 >= 1_072_915_200 else { return false }
        return abs(point.latitude) <= 90 && abs(point.longitude) <= 180
    }

    public func read(_ inputs: [FileInput]) throws -> ImportResult {
        var recording = Recording()
        var warnings: [ImportWarning] = []
        for input in inputs {
            let r = ByteReader(input.data)
            guard r.count >= Self.headerLength else { throw GPSLoggerError(.malformed(line: nil), fileName: input.name) }
            var collector = Warnings(fileName: input.name)
            var cancellation = Cancellation(interval: 4096)
            var points: [TrackPoint] = []
            var offset = Self.headerLength
            while offset + Self.recordLength <= r.count {
                try cancellation.tick()
                let number = (offset - Self.headerLength) / Self.recordLength + 1
                if let point = Self.point(r, offset) {
                    if abs(point.latitude) <= 90, abs(point.longitude) <= 180 {
                        points.append(point)
                    } else {
                        collector.add(.invalidCoordinate, at: number)
                    }
                } else {
                    collector.add(.malformedRecord, at: number)
                }
                offset += Self.recordLength
            }
            if offset < r.count { collector.add(.truncatedFile, at: nil) }
            recording.tracks += Locosys.track(points, fileName: input.name)
            warnings += collector.all
        }
        return ImportResult(recording: recording, warnings: warnings)
    }
}

// MARK: - SBN

/// SiRF binary log files of Locosys GT-11/BGT-11/GT-31/BGT-31 (`sbn.cc`), spec `locosys-import`.
public struct SBNFileFormat: FileFormat {
    static let pidNavigation: UInt8 = 41  // PID_SBN
    static let pidVisibleList: UInt8 = 13
    static let pidInformation: UInt8 = 253  // PID_QRY_INFORMATION
    static let informationLength = 41
    static let navigationLength = 97  // SBN_RECORD_LEN

    public init() {}

    public var id: FileFormatID { .sbn }
    public var displayName: String { L10n.string("format.sbn") }
    public var fileExtensions: [String] { ["sbn"] }

    enum Packet {
        case packet(type: UInt8, payload: Int, length: Int, next: Int)  // payload offset (after the type byte)
        case badChecksum(next: Int)
        case broken
        case end
    }

    /// `read_packet`: A0 A2, length (BE), data, checksum (BE), B0 B3.
    static func packet(_ r: ByteReader, at offset: Int, maxLength: Int) -> Packet {
        if offset >= r.count { return .end }
        guard r.u8(offset) == 0xA0, r.u8(offset + 1) == 0xA2, let size16 = r.u16be(offset + 2) else { return .broken }
        let size = Int(size16)
        guard size >= 1, size <= maxLength, offset + 4 + size + 4 <= r.count,
              r.u8(offset + 4 + size + 2) == 0xB0, r.u8(offset + 4 + size + 3) == 0xB3 else { return .broken }
        let next = offset + 4 + size + 4
        guard r.u16be(offset + 4 + size) == Locosys.checksum(r, from: offset + 4, count: size) else {
            return .badChecksum(next: next)
        }
        return .packet(type: r.u8(offset + 4) ?? 0, payload: offset + 5, length: size - 1, next: next)
    }

    /// `decode_sbn_mode`.
    static func fix(validity: UInt16, mode: UInt8) -> FixType {
        guard validity == 0 else { return FixType.none }
        let fixes: [FixType] = [.none, .none, .none, .twoD, .threeD, .twoD, .threeD, .none]
        let fix = fixes[Int(mode & 7)]
        return mode & 0x80 != 0 && fix == .threeD ? .dgps : fix
    }

    /// `decode_sbn_record`; offsets relative to the payload without the type byte.
    static func point(_ r: ByteReader, _ o: Int) -> TrackPoint? {
        let ms = Int(r.u16be(o + 16) ?? 0)
        guard let year = r.u16be(o + 10),
              let time = Locosys.utc(year: Int(year), month: Int(r.u8(o + 12) ?? 0), day: Int(r.u8(o + 13) ?? 0),
                                     hour: Int(r.u8(o + 14) ?? 0), minute: Int(r.u8(o + 15) ?? 0),
                                     second: Double(ms / 1000) + Double(ms % 1000) / 1000) else { return nil }
        var quality = PositionQuality()
        quality.fix = fix(validity: r.u16be(o) ?? 1, mode: r.u8(o + 3) ?? 0)
        quality.speed = Double(r.u16be(o + 39) ?? 0) * 0.01
        quality.course = Double(r.u16be(o + 41) ?? 0) * 0.01
        quality.satellites = Int(r.u8(o + 87) ?? 0)
        quality.hdop = Double(r.u8(o + 88) ?? 0) * 0.2
        return TrackPoint(latitude: Double(Locosys.i32be(r, o + 22)) * 0.0000001,
                          longitude: Double(Locosys.i32be(r, o + 26)) * 0.0000001,
                          elevation: Double(Locosys.i32be(r, o + 34)) * 0.01, time: time, quality: quality)
    }

    public func matches(prefix: Data) -> Bool {
        if case .packet(let type, _, _, _) = Self.packet(ByteReader(prefix), at: 0, maxLength: Self.informationLength) {
            return type == Self.pidInformation
        }
        return false
    }

    public func read(_ inputs: [FileInput]) throws -> ImportResult {
        var recording = Recording()
        var warnings: [ImportWarning] = []
        for input in inputs {
            let r = ByteReader(input.data)
            guard case .packet(let type, _, _, var offset) = Self.packet(r, at: 0, maxLength: Self.informationLength),
                  type == Self.pidInformation else {
                throw GPSLoggerError(.malformed(line: nil), fileName: input.name)
            }
            var collector = Warnings(fileName: input.name)
            var cancellation = Cancellation(interval: 4096)
            var points: [TrackPoint] = []
            var number = 1
            packets: while true {
                try cancellation.tick()
                number += 1
                switch Self.packet(r, at: offset, maxLength: Self.navigationLength) {
                case .end:
                    break packets
                case .broken:
                    collector.add(.truncatedFile, at: nil)
                    break packets
                case .badChecksum(let next):
                    collector.add(.checksumMismatch, at: number)
                    offset = next
                case .packet(let type, let payload, let length, let next):
                    if type == Self.pidNavigation, length >= 89 {
                        if let point = Self.point(r, payload) {
                            if abs(point.latitude) <= 90, abs(point.longitude) <= 180 {
                                points.append(point)
                            } else {
                                collector.add(.invalidCoordinate, at: number)
                            }
                        } else {
                            collector.add(.malformedRecord, at: number)
                        }
                    }
                    offset = next
                }
            }
            recording.tracks += Locosys.track(points, fileName: input.name)
            warnings += collector.all
        }
        return ImportResult(recording: recording, warnings: warnings)
    }
}
