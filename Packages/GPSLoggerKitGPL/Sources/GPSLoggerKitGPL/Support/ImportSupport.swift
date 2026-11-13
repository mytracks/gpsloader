// Shared helpers for the formats of this package. Own code, not derived from any source project.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GPSLoggerKit

/// Collects warnings per kind while a file is read (count and first occurrence).
struct Warnings {
    let fileName: String
    private var entries: [ImportWarningKind: (count: Int, first: Int?)] = [:]

    init(fileName: String) {
        self.fileName = fileName
    }

    mutating func add(_ kind: ImportWarningKind, at position: Int?, count: Int = 1) {
        if let entry = entries[kind] {
            entries[kind] = (entry.count + count, entry.first)
        } else {
            entries[kind] = (count, position)
        }
    }

    var all: [ImportWarning] {
        ImportWarningKind.allCases.compactMap { kind in
            entries[kind].map { ImportWarning(kind: kind, count: $0.count, fileName: fileName, firstLine: $0.first) }
        }
    }
}

/// Cooperative cancellation: checks the task every `interval` units of work.
struct Cancellation {
    let interval: Int
    private var counter = 0

    init(interval: Int = 4096) {
        self.interval = interval
    }

    mutating func tick() throws {
        counter += 1
        if counter >= interval {
            counter = 0
            try Task.checkCancellation()
        }
    }
}

/// The file name without directory and extension, used as track name.
func trackName(ofFile fileName: String) -> String {
    let base = (fileName as NSString).lastPathComponent
    let name = (base as NSString).deletingPathExtension
    return name.isEmpty ? base : name
}

/// Bounds-checked access to binary data. Reads return `nil` beyond the end.
struct ByteReader {
    let bytes: [UInt8]

    init(_ data: Data) {
        bytes = [UInt8](data)
    }

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    var count: Int { bytes.count }

    func u8(_ offset: Int) -> UInt8? {
        offset >= 0 && offset < bytes.count ? bytes[offset] : nil
    }

    func u16be(_ offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= bytes.count else { return nil }
        return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    func u16le(_ offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= bytes.count else { return nil }
        return UInt16(bytes[offset + 1]) << 8 | UInt16(bytes[offset])
    }

    func u32le(_ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        return (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * UInt32($1)) }
    }

    func u64le(_ offset: Int) -> UInt64? {
        guard offset >= 0, offset + 8 <= bytes.count else { return nil }
        return (0..<8).reduce(UInt64(0)) { $0 | UInt64(bytes[offset + $1]) << (8 * UInt64($1)) }
    }

    /// IEEE 754 single precision, little endian.
    func f32le(_ offset: Int) -> Float? {
        u32le(offset).map { Float(bitPattern: $0) }
    }

    /// IEEE 754 double precision, little endian.
    func f64le(_ offset: Int) -> Double? {
        u64le(offset).map { Double(bitPattern: $0) }
    }

    func u32be(_ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        return (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(bytes[offset + $1]) }
    }
}

/// GPS time (weeks since 1980-01-06 and seconds of the week) to UTC.
enum GPSTime {
    /// 1980-01-06T00:00:00Z.
    static let epoch: TimeInterval = 315_964_800
    static let secondsPerWeek: TimeInterval = 604_800

    /// Start of each GPS-UTC offset (UTC, seconds since 1970) and the offset from then on.
    /// Public IERS Bulletin C data; leap seconds before 1999 are not needed for logger data.
    static let leapSeconds: [(start: TimeInterval, offset: TimeInterval)] = [
        (1_483_228_800, 18),  // 2017-01-01
        (1_435_708_800, 17),  // 2015-07-01
        (1_341_100_800, 16),  // 2012-07-01
        (1_230_768_000, 15),  // 2009-01-01
        (1_136_073_600, 14),  // 2006-01-01
        (915_148_800, 13),    // 1999-01-01
    ]

    /// GPS-UTC offset for a GPS time given as seconds since 1970 (before subtracting the offset).
    static func offset(gpsSeconds: TimeInterval) -> TimeInterval {
        for entry in leapSeconds where gpsSeconds - entry.offset >= entry.start {
            return entry.offset
        }
        return 13
    }

    /// UTC time of an absolute GPS week (not truncated) and second of the week (may exceed one week).
    static func date(absoluteWeek: Int, secondOfWeek: TimeInterval) -> Date {
        let gps = epoch + Double(absoluteWeek) * secondsPerWeek + secondOfWeek
        return Date(timeIntervalSince1970: gps - offset(gpsSeconds: gps))
    }

    /// The absolute week for a 10-bit week number: the cycle that puts it into the 1024 weeks up to `reference`.
    static func absoluteWeek(tenBit week: Int, reference: Date) -> Int {
        let currentWeek = Int((reference.timeIntervalSince1970 - epoch) / secondsPerWeek)
        let cycle = currentWeek / 1024 - (week > currentWeek % 1024 ? 1 : 0)
        return week + max(cycle, 0) * 1024
    }
}

/// Localized strings of this package.
enum L10n {
    static func string(_ key: String, localization: String? = nil) -> String {
        if let localization,
           let path = Bundle.module.path(forResource: localization, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: key, table: nil)
        }
        return Bundle.module.localizedString(forKey: key, value: key, table: nil)
    }
}
