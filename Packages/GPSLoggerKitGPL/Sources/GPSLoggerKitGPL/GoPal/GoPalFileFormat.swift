// Ported from GPSBabel gopal.cc (tag gpsbabel_1_7_0), reader of the format gopal.
// Original: Copyright (C) 2008 Dr. Jürgen Neumann; Copyright (C) 2005 Robert Lipe (based on nmea.c).
// Licensed under the GNU General Public License, version 2 or (at your option) any later version.
// Translated to Swift and modified for gpsloader by Dirk Stichling, 2026-11-13.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GPSLoggerKit

extension FileFormatID {
    public static let gopal: FileFormatID = "gopal"
}

/// Track logs of Medion GoPal navigation devices (`.trk`), spec `gopal-import`.
///
/// Line format (source, lines 35-41): `TICK, TIME UTC, LONG, LAT, HEIGHT, SPEED km/h, FIX, HDOP, SAT`
/// and, in newer files, `, DATE (YYYYMMDD), unknown, bearing`.
public struct GoPalFileFormat: FileFormat {
    /// Defaults of the source's options `maxspeed`, `minspeed` and `clean`.
    static let maxSpeed = 200.0, minSpeed = 0.0
    static let earthRadius = 6_378_137.0

    public init() {}

    public var id: FileFormatID { .gopal }
    public var displayName: String { L10n.string("format.gopal") }
    public var fileExtensions: [String] { ["trk"] }

    static func lines(_ data: Data) -> [Substring] {
        var result: [Substring] = []
        forEachLine(data) { result.append($0) }
        return result
    }

    /// Calls `body` with every line (LF, CR or CRLF), decoded one by one so that cancellation is quick.
    static func forEachLine(_ data: Data, _ body: (Substring) throws -> Void) rethrows {
        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            let bytes = buffer.bindMemory(to: UInt8.self)
            var start = 0
            while start < bytes.count {
                var end = start
                while end < bytes.count, bytes[end] != 0x0A, bytes[end] != 0x0D { end += 1 }
                if end > start {
                    try body(Substring(String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<end]), as: UTF8.self)))
                }
                start = end + 1
            }
        }
    }

    static func fields(_ line: Substring) -> [Substring] {
        line.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces)[...] }
    }

    static func isDigits(_ s: Substring) -> Bool { !s.isEmpty && s.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 } }

    /// `hhmmss` with an optional fraction.
    static func isClock(_ s: Substring) -> Bool {
        let whole = s.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)[0]
        return whole.count == 6 && isDigits(whole) && Double(s) != nil
    }

    public func matches(prefix: Data) -> Bool {
        var lines = Self.lines(prefix).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if lines.count > 1, prefix.last != 0x0A, prefix.last != 0x0D { lines.removeLast() }  // cut off by the prefix
        let checked = lines.prefix(5).map { line in
            let f = Self.fields(line[...])
            return (f.count == 9 || f.count == 12) && Self.isDigits(f[0]) && Self.isClock(f[1])
                && Double(f[2]) != nil && Double(f[3]) != nil
        }
        // The first line and more than half of the checked lines are GoPal lines (others are skipped when reading).
        guard checked.first == true else { return false }
        return checked.filter { $0 }.count * 2 > checked.count
    }

    /// The date from `trackYYYYMMDD_HHMMSS.trk` or `A_YYYYMMDD_HHMMSS.trk` (`gopal_rd_init`), as days since 1970.
    static func dateFromFileName(_ name: String) -> Int? {
        let base = (name as NSString).lastPathComponent
        let digits: Substring
        if base.hasPrefix("track"), base.count > 13 {
            digits = base.dropFirst(5).prefix(8)
        } else if base.hasPrefix("A_"), base.count > 10 {
            digits = base.dropFirst(2).prefix(8)
        } else {
            return nil
        }
        return days(yyyymmdd: digits)
    }

    static func days(yyyymmdd s: Substring) -> Int? {
        guard s.count == 8, isDigits(s), let v = Int(s) else { return nil }
        let year = v / 10_000, month = v / 100 % 100, day = v % 100
        guard (1...12).contains(month), day >= 1, day <= WintecTime.daysInMonth(year: year, month: month) else { return nil }
        return WintecTime.daysSince1970(year: year, month: month, day: day)
    }

    /// Great-circle distance in meters (haversine; the source uses `gcdist`/`radtometers`).
    static func distance(_ a: TrackPoint, _ b: TrackPoint) -> Double {
        let rad = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * rad, dLon = (b.longitude - a.longitude) * rad
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.latitude * rad) * cos(b.latitude * rad) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, h.squareRoot()))
    }

    public func read(_ inputs: [FileInput]) throws -> ImportResult {
        var recording = Recording()
        var warnings: [ImportWarning] = []
        for input in inputs {
            var collector = Warnings(fileName: input.name)
            var cancellation = Cancellation(interval: 4096)
            let fileDate = Self.dateFromFileName(input.name)
            var points: [TrackPoint] = []
            var last: (point: TrackPoint, clock: Int)?
            var latitudeOld = 0.0
            var dayOffset = 0, lastSecondOfDay: Int?
            var undated = 0
            var number = 0

            try Self.forEachLine(input.data) { line in
                try cancellation.tick()
                number += 1
                let f = Self.fields(line)
                guard f.count == 9 || f.count == 12 else { return }  // gopal_check_line: 8 or 11 commas
                guard let clock = Double(f[1]), clock.isFinite, clock >= 0, clock < 1_000_000,
                      let longitude = Double(f[2]), let latitude = Double(f[3]) else {
                    collector.add(.malformedRecord, at: number)
                    return
                }
                let tick = UInt64(f[0]) ?? 0
                let milliseconds = Int((Double(tick % 1_000_000) / 1000).rounded())
                let hms = Int(clock)
                let secondOfDay = (hms / 10_000 % 100) * 3600 + (hms / 100 % 100) * 60 + hms % 100

                var day: Int?
                if f.count == 12 {
                    guard let d = Self.days(yyyymmdd: f[9]) else {
                        collector.add(.malformedRecord, at: number)
                        return
                    }
                    day = d
                } else {
                    if let previous = lastSecondOfDay, secondOfDay < previous { dayOffset += 1 }
                    lastSecondOfDay = secondOfDay
                    day = fileDate.map { $0 + dayOffset }
                }
                // Whole seconds as used for the speed check (`toTime_t`); without a date, the time of day.
                let wholeSeconds = (day ?? dayOffset) * 86_400 + secondOfDay + milliseconds / 1000
                let time = day.map { Date(timeIntervalSince1970: Double($0 * 86_400 + secondOfDay) + Double(milliseconds) / 1000) }

                var quality = PositionQuality()
                quality.speed = Double(f[5]).map { $0 / 3.6 }
                switch Int(f[6]) {
                case 0: quality.fix = FixType.none
                case 2: quality.fix = .twoD
                default: quality.fix = nil
                }
                quality.hdop = Double(f[7])
                quality.satellites = Int(f[8])
                let point = TrackPoint(latitude: latitude, longitude: longitude, elevation: Double(f[4]), time: time,
                                       quality: quality)

                let outOfRange = longitude == 0 || latitude == 0 || abs(latitude) > 90 || abs(longitude) > 180
                // First-time init of the source; unlike the source only with a usable position (design D4).
                if quality.fix != FixType.none, latitudeOld == 0, !outOfRange {
                    latitudeOld = latitude
                    last = (point, wholeSeconds)
                }
                var speed = 0.0
                if let last {
                    speed = 3.6 * Self.distance(last.point, point) / Double(abs(wholeSeconds - last.clock))
                }
                if outOfRange || speed > Self.maxSpeed || speed < Self.minSpeed { return }

                last = (point, wholeSeconds)
                latitudeOld = latitude
                if time == nil { undated += 1 }
                points.append(point)
            }
            if undated > 0 { collector.add(.missingDate, at: nil, count: undated) }
            if !points.isEmpty {
                recording.tracks.append(Track(name: trackName(ofFile: input.name), segments: [TrackSegment(points: points)]))
            }
            warnings += collector.all
        }
        return ImportResult(recording: recording, warnings: warnings)
    }
}
