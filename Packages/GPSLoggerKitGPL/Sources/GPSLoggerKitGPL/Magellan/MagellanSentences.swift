// Ported from GPSBabel magproto.cc and magellan.h (tag gpsbabel_1_7_0), sentence layer of the formats
// magellan and magellanx.
// Original: Copyright (C) 2002, 2003, 2004, 2005, 2006, 2007, 2008, 2010 Robert Lipe (magproto.cc);
// Copyright (C) 2002-2005 Robert Lipe (magellan.h).
// Licensed under the GNU General Public License, version 2 or (at your option) any later version.
// Translated to Swift and modified for gpsloader by Dirk Stichling, 2026-11-13.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GPSLoggerKit

/// Sentences of the Magellan protocol (`$PMGN…*XX`), shared by the serial driver and the SD files
/// (specs `magellan-device` and `magellan-import`).
enum MagellanSentences {
    /// `meridian_model` (magellan.h) with the product IDs of `pid_to_model` (magproto.cc).
    enum Model: Sendable, Equatable {
        case gps315320, map410, map330, gps310, meridian, sportrak

        /// `pid_to_model`.
        static func forProductID(_ id: Int) -> (model: Model, name: String)? {
            switch id {
            case 19: (.gps315320, "ColorTrak")
            case 24: (.gps315320, "GPS 315/320")
            case 25: (.map410, "Map 410")
            case 30: (.map330, "Map 330")
            case 31: (.gps310, "GPS 310")
            case 33: (.meridian, "Meridian")
            case 35: (.meridian, "ProMark 2")
            case 36: (.sportrak, "SporTrak Map/Pro")
            case 37: (.sportrak, "SporTrak")
            case 38: (.meridian, "FX324 Plotter")
            case 39: (.meridian, "Meridian Color")
            case 40: (.meridian, "FX324C Plotter")
            case 41: (.sportrak, "Sportrak Color")
            case 42: (.sportrak, "Sportrak Marine")
            case 43: (.meridian, "Meridian Marine")
            case 44: (.sportrak, "Sportrak Topo")
            case 45: (.sportrak, "Mystic")
            case 46: (.meridian, "MobileMapper")
            case 110: (.meridian, "Explorist 100")
            case 111: (.meridian, "Explorist 200")
            default: nil
            }
        }

        /// `mag_verparse`: the GPS 315/320 and Map 410 family does not understand `NMEAOFF`.
        var understandsNMEAOff: Bool { self != .gps315320 && self != .map410 }
    }

    /// `mag_checksum`: XOR of all characters.
    static func checksum<S: Sequence>(_ body: S) -> UInt8 where S.Element == UInt8 {
        body.reduce(0, ^)
    }

    /// `mag_writemsg`: `$<body>*XX\r\n`.
    static func command(_ body: String) -> [UInt8] {
        Array("$\(body)*\(String(format: "%02X", checksum(body.utf8)))\r\n".utf8)
    }

    /// A received sentence: the text without trailing non-printable characters and whether its checksum is right.
    struct Received: Sendable, Equatable {
        var text: String
        var checksumIsValid: Bool

        /// The text starts with `token` (`IS_TKN`).
        func starts(with token: String) -> Bool { text.hasPrefix(token) }
    }

    /// `mag_readmsg`: `nil` for lines that are too short (fewer than 5 characters) or don't start with `$`.
    ///
    /// Like the source, the last two characters are the checksum and the body is everything between `$`
    /// and the three characters before the end.
    static func parse(_ line: some StringProtocol) -> Received? {
        var bytes = Array(line.utf8)
        while let last = bytes.last, !(0x20...0x7E).contains(last) { bytes.removeLast() }
        guard bytes.first == 0x24 else { return nil }
        guard bytes.count >= 5 else { return nil }
        let text = String(decoding: bytes, as: UTF8.self)
        let sumText = String(decoding: bytes.suffix(2), as: UTF8.self)
        let valid = UInt8(sumText, radix: 16).map { $0 == checksum(bytes[1..<(bytes.count - 3)]) } ?? false
        return Received(text: text, checksumIsValid: valid)
    }

    /// `parse_istring`: fields separated by commas (field 0 is the sentence name).
    static func fields(_ text: String) -> [Substring] {
        text.split(separator: ",", omittingEmptySubsequences: false)
    }

    /// `ddmm2degrees` (util.cc) with the hemisphere applied first, like the source.
    static func degrees(_ field: Substring, _ hemisphere: Substring, negative: Character) -> Double {
        var value = Double(field.trimmingCharacters(in: .whitespaces)) ?? 0
        if hemisphere.first == negative { value = -value }
        let whole = Double(Int(value / 100))
        return whole + ((value / 100 - whole) * 100) / 60
    }

    /// The leading integer of a field, like `atoi`/`%d`.
    static func leadingInteger(_ field: Substring) -> Int? {
        let trimmed = field.drop { $0 == " " }
        var digits = trimmed.prefix { $0.isASCII && $0.isNumber }
        if digits.isEmpty, let sign = trimmed.first, sign == "-" || sign == "+" {
            digits = trimmed.dropFirst().prefix { $0.isASCII && $0.isNumber }
            return Int(digits).map { sign == "-" ? -$0 : $0 }
        }
        return Int(digits)
    }

    /// `mag_trkparse`: `$PMGNTRK,lat,N,lon,W,alt,M,hhmmss.ss,A,name,ddmmyy*XX`.
    static func trackPoint(_ text: String) -> TrackPoint {
        let f = fields(text)
        func field(_ i: Int) -> Substring { i < f.count ? f[i] : "" }
        let latitude = degrees(field(1), field(2), negative: "S")
        let longitude = degrees(field(3), field(4), negative: "W")
        // `int alt = atof(...)`: truncated towards zero.
        let altitude = Double(Int(Double(field(5).prefix { $0 != "*" }) ?? 0))
        // `sscanf("%d.%d")` on the time; the fraction counts as hundredths (`10.0 * fracsecs` ms).
        let clock = field(7).split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let hms = leadingInteger(clock[0]) ?? 0
        let fraction = clock.count > 1 ? leadingInteger(clock[1]) ?? 0 : 0
        let dmy = leadingInteger(field(10)) ?? 0
        let time = Locosys.utc(year: 2000 + dmy % 100, month: dmy / 100 % 100, day: dmy / 10_000 % 100,
                               hour: hms / 10_000 % 100, minute: hms / 100 % 100,
                               second: Double(hms % 100) + Double(fraction) / 100)
        return TrackPoint(latitude: latitude, longitude: longitude, elevation: altitude, time: time)
    }

    /// `mag_wptparse`: `$PMGNWPL,lat,N,lon,W,alt,M,name,comment,icon*XX`. The icon is not kept.
    static func waypoint(_ text: String) -> Waypoint {
        let f = fields(text)
        func field(_ i: Int) -> Substring { i < f.count ? f[i] : "" }
        let latitude = degrees(field(1), field(2), negative: "S")
        let longitude = degrees(field(3), field(4), negative: "W")
        let altitude = Double(leadingInteger(field(5)) ?? 0)
        let name = String(field(7))
        let comment = dequote(String(field(8)))
        return Waypoint(latitude: latitude, longitude: longitude, elevation: altitude,
                        name: name.isEmpty ? nil : name, comment: comment.isEmpty ? nil : comment)
    }

    /// `mag_dequote`: `ESC h h` stands for the character with hex code `hh` (non-printable ones become `$`);
    /// `ESC F F F…` is corrupted data and is removed. A truncated escape ends the text.
    static func dequote(_ text: String) -> String {
        let hex = Array("0123456789ABCDEF".utf8)
        var bytes = Array(text.utf8)
        var i = 0
        while i < bytes.count {
            guard bytes[i] == 0x1B else { i += 1; continue }
            guard bytes.count - i >= 3 else { bytes.removeSubrange(i...); break }
            guard let high = hex.firstIndex(of: bytes[i + 1]), let low = hex.firstIndex(of: bytes[i + 2]) else {
                bytes.remove(at: i)  // the source would loop forever here
                continue
            }
            let value = high * 16 + low
            if value == 255 {
                var end = i + 1
                while end < bytes.count, bytes[end] == 0x46 { end += 1 }
                bytes.removeSubrange(i..<end)
            } else {
                bytes.replaceSubrange(i...(i + 2), with: [(0x20...0x7E).contains(value) ? UInt8(value) : 0x24])
                i += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
