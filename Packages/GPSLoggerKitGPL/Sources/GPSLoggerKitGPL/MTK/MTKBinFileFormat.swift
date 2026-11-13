// Ported from GPSBabel mtk_logger.cc (tag gpsbabel_1_7_0), file reader of the formats mtk-bin and m241-bin.
// Original: Copyright (C) 2007 Per Borgentun; with inspiration from wbt-200.c, Copyright (C) 2006 Andy Armstrong.
// Licensed under the GNU General Public License, version 2 or (at your option) any later version.
// Translated to Swift and modified for gpsloader by Dirk Stichling, 2026-11-13.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GPSLoggerKit

extension FileFormatID {
    public static let mtkBin: FileFormatID = "mtk-bin"
    public static let m241Bin: FileFormatID = "m241-bin"
}

/// Memory dumps of MTK based loggers (iBlue 747, Qstarz BT-Q1000, …) as written by gpsbabel's `mtk`
/// driver (`data.bin`), spec `mtk-import`.
public struct MTKBinFileFormat: FileFormat {
    public init() {}

    public var id: FileFormatID { .mtkBin }
    public var displayName: String { L10n.string("format.mtk-bin") }
    public var fileExtensions: [String] { ["bin"] }

    public func matches(prefix: Data) -> Bool {
        MTKDump.detect(ByteReader(prefix)) == .mtk
    }

    public func read(_ inputs: [FileInput]) throws -> ImportResult {
        try MTKDump.read(inputs, device: .mtk)
    }
}

/// Memory dumps of Holux M-241, GPSport 245 and M-1200 loggers (gpsbabel `m241-bin`), spec `mtk-import`.
public struct M241BinFileFormat: FileFormat {
    public init() {}

    public var id: FileFormatID { .m241Bin }
    public var displayName: String { L10n.string("format.m241-bin") }
    public var fileExtensions: [String] { ["bin"] }

    public func matches(prefix: Data) -> Bool {
        MTKDump.detect(ByteReader(prefix)) == .holuxM241
    }

    public func read(_ inputs: [FileInput]) throws -> ImportResult {
        try MTKDump.read(inputs, device: .holuxM241)
    }
}

/// Decoder of one dump (`file_read`, `mtk_parse`, `mtk_parse_info` and `add_trackpoint` of the source).
struct MTKDump {
    enum Device: Equatable {
        case mtk, holuxM241, holuxGR245
    }

    // Field bits of the format mask (`DATA_TYPES` of the source).
    enum Field: Int, CaseIterable {
        case utc = 0, valid, latitude, longitude, height, speed, heading, dsta, dage, pdop, hdop, vdop, nsat, sid,
             elevation, azimuth, snr, rcr, millisecond, distance
    }

    static let blockSize = 0x10000
    static let dataStart = 0x200
    static let infoLength = 16

    // Track events (`MTK_EVT_*`).
    static let eventStart = 1 << 7
    static let eventWaypoint = 1 << 16

    private(set) var tracks: [[TrackPoint]] = []
    private(set) var waypoints: [Waypoint] = []
    var warnings: Warnings
    private var device: Device
    private var mask: UInt32 = 0
    private var events = 0

    init(fileName: String, device: Device) {
        warnings = Warnings(fileName: fileName)
        self.device = device
    }

    static func read(_ inputs: [FileInput], device: Device) throws -> ImportResult {
        var recording = Recording()
        var warnings: [ImportWarning] = []
        for input in inputs {
            var dump = MTKDump(fileName: input.name, device: device)
            try dump.read(ByteReader(input.data))
            let nonEmpty = dump.tracks.filter { !$0.isEmpty }
            let base = trackName(ofFile: input.name)
            for (index, points) in nonEmpty.enumerated() {
                let name = nonEmpty.count == 1 ? base : "\(base) (\(index + 1))"
                recording.tracks.append(Track(name: name, segments: [TrackSegment(points: points)]))
            }
            recording.waypoints += dump.waypoints
            warnings += dump.warnings.all
        }
        return ImportResult(recording: recording, warnings: warnings)
    }

    /// Size of a field for the current device (`log_type` of the source, adjusted by `file_init`
    /// and `holux245_init`). Bits above 19 have no data.
    func size(_ bit: Int) -> Int {
        guard let field = Field(rawValue: bit) else { return 0 }
        switch field {
        case .utc, .speed, .heading, .dage, .sid: return device == .holuxGR245 && field == .speed ? 3 : 4
        case .latitude, .longitude: return device == .mtk ? 8 : 4
        case .height: return device == .mtk ? 4 : (device == .holuxGR245 ? 4 : 3)
        case .distance: return 8
        default: return 2
        }
    }

    // MARK: Reading

    mutating func read(_ data: ByteReader) throws {
        guard data.count >= 20 else { return warnings.add(.truncatedFile, at: nil) }
        var header = 0
        if let policy = data.u16le(6), policy != 0x0104, policy != 0x0106, data.count > Self.blockSize {
            header = Self.blockSize
        }
        mask = data.u32le(header + 2) ?? 0
        if device != .mtk { mask &= 0x7FFF_FFFF }

        var cancellation = Cancellation(interval: 1024)
        var blockStart = 0
        blocks: while blockStart + Self.dataStart < data.count {
            var offset = blockStart + Self.dataStart
            let blockEnd = min(blockStart + Self.blockSize, data.count)
            while offset < blockEnd {
                try cancellation.tick()
                if Self.isInfoBlock(data, offset) {
                    info(data, offset)
                    offset += Self.infoLength
                } else if device != .mtk, Self.isHolux(data, offset) {
                    offset += holux(data, offset)
                } else if (0..<4).allSatisfy({ data.u8(offset + $0) == 0xFF }) || blockEnd - offset < 4 {
                    break
                } else {
                    guard let length = record(data, offset, end: blockEnd) else {
                        if blockEnd < data.count { break }  // a record crossing into the next block: continue there
                        warnings.add(.truncatedFile, at: nil)
                        break blocks
                    }
                    offset += length
                }
            }
            blockStart += Self.blockSize
        }
    }

    static func isInfoBlock(_ data: ByteReader, _ offset: Int) -> Bool {
        (0..<6).allSatisfy { data.u8(offset + $0) == 0xAA } && (12..<16).allSatisfy { data.u8(offset + $0) == 0xBB }
    }

    static func isHolux(_ data: ByteReader, _ offset: Int) -> Bool {
        Array("HOLUX".utf8).enumerated().allSatisfy { data.u8(offset + $0.offset) == $0.element }
    }

    private static func matches(_ data: ByteReader, _ offset: Int, _ text: String) -> Bool {
        Array(text.utf8).enumerated().allSatisfy { data.u8(offset + $0.offset) == $0.element }
    }

    /// `mtk_parse_info`.
    private mutating func info(_ data: ByteReader, _ offset: Int) {
        let value = Int(data.u16le(offset + 8) ?? 0)
        switch data.u8(offset + 7) {
        case 0x02:
            var bits = data.u32le(offset + 8) ?? 0
            if device != .mtk { bits &= 0x7FFF_FFFF }
            if device == .holuxGR245 { bits &= ~(UInt32(1) << 27) }
            mask = bits
        case 0x03, 0x04:
            if device != .mtk { events |= Self.eventStart }
        case 0x07:
            if value == 0x0106, device == .mtk { events |= Self.eventStart }
        default:
            break
        }
    }

    /// A Holux identification string; returns its length.
    private mutating func holux(_ data: ByteReader, _ offset: Int) -> Int {
        if Self.matches(data, offset + 10, "WAYPNT") { events |= Self.eventWaypoint }
        if Self.matches(data, offset, "HOLUXGR245") || Self.matches(data, offset, "HOLUXM1200") { device = .holuxGR245 }
        return Self.matches(data, offset + 16, "    ") ? 20 : 16
    }

    private struct Item {
        var time: UInt32 = 0, valid: UInt16 = 0
        var latitude = 0.0, longitude = 0.0
        var height: Double?, speed: Double?, heading: Double?
        var pdop: Double?, hdop: Double?, vdop: Double?
        var satellitesUsed: Int?, rcr: UInt16 = 0, millisecond: UInt16 = 0
    }

    /// One log record (`mtk_parse`); returns its length, or `nil` when it does not fit before `end`.
    private mutating func record(_ data: ByteReader, _ start: Int, end: Int) -> Int? {
        var item = Item()
        var i = start
        var crc: UInt8 = 0
        func consume(_ count: Int) -> Bool {
            guard i + count <= end else { return false }
            for k in 0..<count { crc ^= data.u8(i + k) ?? 0 }
            i += count
            return true
        }

        for bit in 0..<32 where mask & (UInt32(1) << UInt32(bit)) != 0 {
            let field = Field(rawValue: bit)
            let size = size(bit)
            if field == .elevation || field == .azimuth || field == .snr { continue }  // part of the SID blocks
            if field == .sid {
                guard i + 4 <= end else { return nil }
                let count = min(Int(data.u16le(i + 2) ?? 0), 32)
                var blockSize = 4
                if count > 0 {
                    for optional in [Field.elevation, .azimuth, .snr] where mask & (UInt32(1) << UInt32(optional.rawValue)) != 0 {
                        blockSize += 2
                    }
                }
                for _ in 0..<max(count, 1) {
                    guard consume(blockSize) else { return nil }
                }
                continue
            }
            guard i + size <= end else { return nil }
            switch field {
            case .utc: item.time = data.u32le(i) ?? 0
            case .valid: item.valid = data.u16le(i) ?? 0
            case .latitude: item.latitude = coordinate(data, i)
            case .longitude: item.longitude = coordinate(data, i)
            case .height:
                if device == .holuxGR245 {
                    item.speed = Double(data.u32le(i) ?? 0) / 100  // cm/s in the height slot
                } else {
                    item.height = Double(device == .mtk ? data.f32le(i) ?? 0 : Self.float24(data, i))
                }
            case .speed:
                if device == .holuxGR245 {
                    item.height = Double(Self.float24(data, i))
                } else {
                    item.speed = Double(data.f32le(i) ?? 0) / 3.6
                }
            case .heading: item.heading = Double(data.f32le(i) ?? 0)
            case .pdop: item.pdop = Double(data.u16le(i) ?? 0) / 100
            case .hdop: item.hdop = Double(data.u16le(i) ?? 0) / 100
            case .vdop: item.vdop = Double(data.u16le(i) ?? 0) / 100
            case .nsat: item.satellitesUsed = Int(data.u8(i + 1) ?? 0)
            case .rcr: item.rcr = data.u16le(i) ?? 0
            case .millisecond: item.millisecond = data.u16le(i) ?? 0
            default: break
            }
            _ = consume(size)
        }

        if device == .mtk {
            guard let star = data.u8(i) else { return nil }
            if star == 0x2A {  // "*"
                i += 1
            } else if star == 0xFF {
                // The checksum was not written (power off): skip the record without a point.
                events = 0
                return i + 2 - start
            }
        }
        guard let checksum = data.u8(i) else { return nil }
        i += 1
        if checksum != crc {
            warnings.add(.checksumMismatch, at: nil)
            if events & Self.eventStart != 0 { tracks.append([]) }  // keep the track split of the dropped record
        } else {
            add(item)
        }
        events = 0
        return i - start
    }

    private func coordinate(_ data: ByteReader, _ offset: Int) -> Double {
        device == .mtk ? data.f64le(offset) ?? 0 : Double(data.f32le(offset) ?? 0)
    }

    /// Holux heights: the upper three bytes of a little endian float (the lowest byte is zero).
    static func float24(_ data: ByteReader, _ offset: Int) -> Float {
        let bits = UInt32(data.u8(offset) ?? 0) << 8 | UInt32(data.u8(offset + 1) ?? 0) << 16
            | UInt32(data.u8(offset + 2) ?? 0) << 24
        return Float(bitPattern: bits)
    }

    private func has(_ field: Field) -> Bool {
        mask & (UInt32(1) << UInt32(field.rawValue)) != 0
    }

    /// `add_trackpoint`.
    private mutating func add(_ item: Item) {
        if tracks.isEmpty || events & Self.eventStart != 0 { tracks.append([]) }
        guard has(.latitude), has(.longitude) else { return }
        guard item.latitude.isFinite, item.longitude.isFinite, abs(item.latitude) <= 90, abs(item.longitude) <= 180 else {
            return warnings.add(.invalidCoordinate, at: nil)
        }
        var quality = PositionQuality()
        if has(.valid) {
            switch item.valid {
            case 0x0001: quality.fix = FixType.none
            case 0x0002: quality.fix = .threeD
            case 0x0004: quality.fix = .dgps
            default: quality.fix = nil
            }
            let known = [0x0002, 0x0004, 0x0008].contains(Int(item.valid))
            let bogus = (abs(item.latitude - 90) < 0.000001 || abs(item.latitude) < 0.000001) && abs(item.longitude) < 0.000001
            if !known, bogus { return }
        }
        if has(.pdop) { quality.pdop = item.pdop }
        if has(.hdop) { quality.hdop = item.hdop }
        if has(.vdop) { quality.vdop = item.vdop }
        if has(.heading) { quality.course = item.heading }
        if has(.speed) { quality.speed = item.speed }
        if has(.nsat) { quality.satellites = item.satellitesUsed }

        var time: Date?
        if has(.utc) {
            let milliseconds = has(.millisecond) ? Double(item.millisecond) / 1000 : 0
            time = Date(timeIntervalSince1970: Double(item.time) + milliseconds)
        }
        let elevation = has(.height) ? item.height : nil
        let point = TrackPoint(latitude: item.latitude, longitude: item.longitude, elevation: elevation, time: time,
                               quality: quality)
        tracks[tracks.count - 1].append(point)

        if has(.rcr) && item.rcr & 0x0008 != 0 || events & Self.eventWaypoint != 0 {
            waypoints.append(Waypoint(latitude: point.latitude, longitude: point.longitude, elevation: point.elevation,
                                      time: time, name: "POI \(waypoints.count + 1)", quality: quality))
        }
    }

    // MARK: Detection (design D5)

    static func detect(_ data: ByteReader) -> Device? {
        guard let bits = data.u32le(2), let policy = data.u16le(6), policy == 0x0104 || policy == 0x0106 else { return nil }
        let required: UInt32 = 1 << 0 | 1 << 2 | 1 << 3
        guard bits & required == required, bits & 0x7FF0_0000 == 0 else { return nil }
        var offset = dataStart
        while isInfoBlock(data, offset) { offset += infoLength }
        if isHolux(data, offset) || bits & 0x8000_0000 != 0 { return .holuxM241 }
        if offset > dataStart { return .mtk }
        var probe = MTKDump(fileName: "", device: .mtk)
        probe.mask = bits
        // A record with "*" and a correct checksum creates a (possibly empty) track; one without "*" does not.
        guard probe.record(data, offset, end: data.count) != nil, probe.warnings.all.isEmpty, !probe.tracks.isEmpty else {
            return nil
        }
        return .mtk
    }
}
