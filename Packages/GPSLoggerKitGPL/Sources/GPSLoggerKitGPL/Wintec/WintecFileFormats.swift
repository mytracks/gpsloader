// Ported from GPSBabel (tag gpsbabel_1_7_0):
//   wintec_tes.cc: Copyright (C) 2010 Robert Lipe.
//   wbt-200.cc (file reader of wbt-bin and wbt-tk1): Copyright (C) 2006 Andy Armstrong.
// Both licensed under the GNU General Public License, version 2 or (at your option) any later version.
// Translated to Swift and modified for gpsloader by Dirk Stichling, 2026-11-13.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GPSLoggerKit

extension FileFormatID {
    public static let wintecTES: FileFormatID = "wintec-tes"
    public static let wbtBin: FileFormatID = "wbt-bin"
    public static let wbtTK1: FileFormatID = "wbt-tk1"
}

/// The packed Wintec time stamp (`wintec_date_to_time`, `_SPLIT_DATE`, `decode_date`, `check_date`).
enum WintecTime {
    struct Fields: Equatable {
        var year, month, day, hour, minute, second: Int
    }

    static func fields(_ value: UInt32) -> Fields {
        Fields(year: 2000 + Int(value >> 26 & 0x3F), month: Int(value >> 22 & 0x0F), day: Int(value >> 17 & 0x1F),
               hour: Int(value >> 12 & 0x1F), minute: Int(value >> 6 & 0x3F), second: Int(value & 0x3F))
    }

    /// `check_date` of wbt-200.cc: plausible fields and a year from 2004 on.
    static func isValid(_ value: UInt32) -> Bool {
        let f = fields(value)
        return f.second < 60 && f.minute < 60 && f.hour < 24 && (1...31).contains(f.day) && (1...12).contains(f.month)
            && f.year >= 2004
    }

    /// The time, or `nil` for impossible fields.
    static func date(_ value: UInt32) -> Date? {
        let f = fields(value)
        guard f.second < 60, f.minute < 60, f.hour < 24, (1...12).contains(f.month), f.day >= 1,
              f.day <= daysInMonth(year: f.year, month: f.month) else { return nil }
        let days = daysSince1970(year: f.year, month: f.month, day: f.day)
        return Date(timeIntervalSince1970: TimeInterval(days * 86_400 + f.hour * 3600 + f.minute * 60 + f.second))
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// Days from 1970-01-01 to a civil date (proleptic Gregorian calendar).
    static func daysSince1970(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
        return era * 146_097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719_468
    }
}

/// Collects tracks and waypoints with the naming rules of this package.
struct WintecResult {
    var tracks: [[TrackPoint]] = []
    var waypoints: [Waypoint] = []
    var newTrack = true

    mutating func add(_ point: TrackPoint) {
        if newTrack || tracks.isEmpty {
            tracks.append([])
            newTrack = false
        }
        tracks[tracks.count - 1].append(point)
    }

    mutating func addWaypoint(_ point: TrackPoint) {
        waypoints.append(Waypoint(latitude: point.latitude, longitude: point.longitude, elevation: point.elevation,
                                  time: point.time, name: "POI \(waypoints.count + 1)"))
    }

    func append(to recording: inout Recording, fileName: String) {
        let nonEmpty = tracks.filter { !$0.isEmpty }
        let base = trackName(ofFile: fileName)
        for (index, points) in nonEmpty.enumerated() {
            recording.tracks.append(Track(name: nonEmpty.count == 1 ? base : "\(base) (\(index + 1))",
                                          segments: [TrackSegment(points: points)]))
        }
        recording.waypoints += waypoints
    }
}

private func coordinate(_ reader: ByteReader, _ offset: Int) -> Double {
    Double(Int32(bitPattern: reader.u32le(offset) ?? 0)) / 10_000_000
}

// MARK: - TES

/// TES files written to the SD card by the Wintec WBT-202 (`wintec_tes.cc`), spec `wintec-import`.
public struct WintecTESFileFormat: FileFormat {
    static let recordLength = 16

    public init() {}

    public var id: FileFormatID { .wintecTES }
    public var displayName: String { L10n.string("format.wintec-tes") }
    public var fileExtensions: [String] { ["tes"] }

    public func matches(prefix: Data) -> Bool {
        let reader = ByteReader(prefix)
        let count = reader.count / Self.recordLength
        guard count >= 2 else { return false }
        return (0..<count).allSatisfy { k in
            let o = k * Self.recordLength
            guard let flags = reader.u16le(o), flags <= 0x0007, let time = reader.u32le(o + 2) else { return false }
            return WintecTime.isValid(time) && abs(coordinate(reader, o + 6)) <= 90 && abs(coordinate(reader, o + 10)) <= 180
        }
    }

    public func read(_ inputs: [FileInput]) throws -> ImportResult {
        var recording = Recording()
        var warnings: [ImportWarning] = []
        for input in inputs {
            var collector = Warnings(fileName: input.name)
            var result = WintecResult()
            var cancellation = Cancellation(interval: 4096)
            let reader = ByteReader(input.data)
            var offset = 0
            while offset + Self.recordLength <= reader.count {
                try cancellation.tick()
                let flags = reader.u16le(offset) ?? 0
                let latitude = coordinate(reader, offset + 6), longitude = coordinate(reader, offset + 10)
                if let time = WintecTime.date(reader.u32le(offset + 2) ?? 0) {
                    if abs(latitude) <= 90, abs(longitude) <= 180 {
                        let altitude = Double(Int16(bitPattern: reader.u16le(offset + 14) ?? 0))
                        let point = TrackPoint(latitude: latitude, longitude: longitude, elevation: altitude, time: time)
                        if flags & 0x02 != 0 { result.addWaypoint(point) }
                        result.add(point)
                    } else {
                        collector.add(.invalidCoordinate, at: offset / Self.recordLength + 1)
                    }
                } else {
                    collector.add(.malformedRecord, at: offset / Self.recordLength + 1)
                }
                offset += Self.recordLength
            }
            if offset < reader.count { collector.add(.truncatedFile, at: nil) }
            result.append(to: &recording, fileName: input.name)
            warnings += collector.all
        }
        return ImportResult(recording: recording, warnings: warnings)
    }
}

// MARK: - BIN and TK1

/// Shared reader of `wbt-bin` and `wbt-tk1` (`file_read` of wbt-200.cc detects the kind by the header).
enum WintecLog {
    static let tk1Magic = Array("WintecLogFormat".utf8) + [0]
    static let tk1DataOffset = 0x400
    static let tk1EndFlag: UInt32 = 0x0400_0000
    static let recordLengths = [12, 16]  // RECLEN_V1, RECLEN_V2

    static func isTK1(_ reader: ByteReader) -> Bool {
        tk1Magic.enumerated().allSatisfy { reader.u8($0.offset) == $0.element }
    }

    static func read(_ inputs: [FileInput]) throws -> ImportResult {
        var recording = Recording()
        var warnings: [ImportWarning] = []
        for input in inputs {
            let reader = ByteReader(input.data)
            var collector = Warnings(fileName: input.name)
            var result = WintecResult()
            if isTK1(reader) {
                try readTK1(reader, into: &result, warnings: &collector)
            } else {
                guard let length = recordLengths.first(where: { reader.count % $0 == 0 && isValid(reader, length: $0) }) else {
                    throw GPSLoggerError(.malformed(line: nil), fileName: input.name)
                }
                try readBin(reader, length: length, into: &result)
            }
            result.append(to: &recording, fileName: input.name)
            warnings += collector.all
        }
        return ImportResult(recording: recording, warnings: warnings)
    }

    /// `is_valid`: every complete record has a valid time stamp.
    static func isValid(_ reader: ByteReader, length: Int) -> Bool {
        stride(from: 0, through: reader.count - length, by: length).allSatisfy { WintecTime.isValid(reader.u32le($0) ?? 0) }
    }

    /// `wbt200_data_chunk`.
    static func readBin(_ reader: ByteReader, length: Int, into result: inout WintecResult) throws {
        var cancellation = Cancellation(interval: 4096)
        for offset in stride(from: 0, through: reader.count - length, by: length) {
            try cancellation.tick()
            var latitude = coordinate(reader, offset + 4)
            let longitude = coordinate(reader, offset + 8)
            let altitude = length >= 16 ? Double(Int32(bitPattern: reader.u32le(offset + 12) ?? 0)) / 10 : nil
            if latitude >= 100 {
                latitude -= 100
                result.newTrack = true
            } else if latitude <= -100 {
                latitude += 100
                result.newTrack = true
            }
            result.add(TrackPoint(latitude: latitude, longitude: longitude, elevation: altitude,
                                  time: WintecTime.date(reader.u32le(offset) ?? 0)))
        }
    }

    /// `wbt201_data_chunk`.
    static func readTK1(_ reader: ByteReader, into result: inout WintecResult, warnings: inout Warnings) throws {
        _ = try readWBT201Records(reader, from: tk1DataOffset, into: &result, warnings: &warnings)
    }

    /// Records of 16 bytes from `from` on (`wbt201_process_chunk`); returns `true` when the end flag was reached.
    static func readWBT201Records(_ reader: ByteReader, from: Int, into result: inout WintecResult,
                                  warnings: inout Warnings) throws -> Bool {
        var cancellation = Cancellation(interval: 4096)
        var offset = from
        while offset + 16 <= reader.count {
            try cancellation.tick()
            defer { offset += 16 }
            if (0..<16).allSatisfy({ reader.u8(offset + $0) == 0 }) { continue }
            let flags = reader.u16le(offset) ?? 0
            let stamp = reader.u32le(offset + 2) ?? 0
            if stamp == tk1EndFlag { return true }
            guard let time = WintecTime.date(stamp) else {
                warnings.add(.malformedRecord, at: (offset - from) / 16 + 1)
                continue
            }
            let point = TrackPoint(latitude: coordinate(reader, offset + 6), longitude: coordinate(reader, offset + 10),
                                   elevation: Double(Int16(bitPattern: reader.u16le(offset + 14) ?? 0)), time: time)
            if flags & 0x02 != 0 { result.addWaypoint(point) }
            if flags & 0x01 != 0 { result.newTrack = true }
            result.add(point)
        }
        return false
    }

    /// Detection of BIN files (design D5).
    static func looksLikeBin(_ reader: ByteReader) -> Bool {
        guard !isTK1(reader) else { return false }
        return recordLengths.contains { length in
            let count = reader.count / length
            guard count >= 2 else { return false }
            return (0..<count).allSatisfy { k in
                let o = k * length
                return WintecTime.isValid(reader.u32le(o) ?? 0) && abs(coordinate(reader, o + 4)) < 190
                    && abs(coordinate(reader, o + 8)) <= 180
            }
        }
    }
}

/// Memory dumps of the Wintec WBT-100/200 (`wbt-bin`), spec `wintec-import`.
public struct WintecBinFileFormat: FileFormat {
    public init() {}

    public var id: FileFormatID { .wbtBin }
    public var displayName: String { L10n.string("format.wbt-bin") }
    public var fileExtensions: [String] { ["bin"] }

    public func matches(prefix: Data) -> Bool {
        WintecLog.looksLikeBin(ByteReader(prefix))
    }

    public func read(_ inputs: [FileInput]) throws -> ImportResult {
        try WintecLog.read(inputs)
    }
}

/// TK1 files of the Wintec WBT-201, G-Rays 2 and WSG-1000 (`wbt-tk1`), spec `wintec-import`.
public struct WintecTK1FileFormat: FileFormat {
    public init() {}

    public var id: FileFormatID { .wbtTK1 }
    public var displayName: String { L10n.string("format.wbt-tk1") }
    public var fileExtensions: [String] { ["tk1"] }

    public func matches(prefix: Data) -> Bool {
        WintecLog.isTK1(ByteReader(prefix))
    }

    public func read(_ inputs: [FileInput]) throws -> ImportResult {
        try WintecLog.read(inputs)
    }
}
