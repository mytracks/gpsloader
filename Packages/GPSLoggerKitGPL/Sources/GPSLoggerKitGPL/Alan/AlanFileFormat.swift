// Ported from GPSBabel alan.cc (tag gpsbabel_1_7_0), reader of the format alantrl.
// Original: Copyright (C) 2007 Gunar Megger; Copyright (C) 2002-2014 Robert Lipe.
// Licensed under the GNU General Public License, version 2 or (at your option) any later version.
// Translated to Swift and modified for gpsloader by Dirk Stichling, 2026-11-13.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GPSLoggerKit

extension FileFormatID {
    public static let alanTrl: FileFormatID = "alantrl"
}

/// Track log files of the Alan Map500 (`.trl`, OS 2.xx), spec `alan-import`.
///
/// Layout (`struct trldata`, little endian): four blocks of 0x10000 bytes with two track logs each, then
/// the log header at 0x40000. The format stores no times.
public struct AlanFileFormat: FileFormat {
    public init() {}

    public var id: FileFormatID { .alanTrl }
    public var displayName: String { L10n.string("format.alantrl") }
    public var fileExtensions: [String] { ["trl"] }

    static let maxTracks = 8  // MAXTRK
    static let maxPoints = 2500  // MAXPTINTRK
    static let headerOffset = 0x40000
    static let headerID: UInt32 = 0x38CB_1200  // TRL_HDR_ID
    static let trackHeaderLength = 44
    static let headerLength = 16 + maxTracks * trackHeaderLength
    static let minimumLength = headerOffset + headerLength
    static let trackLogLength = maxPoints * 12
    /// MAP500_PT_SCALE, MAP500_ALTITUDE_SCALE, MAP500_SPEED_SCALE.
    static let pointScale = 36000.0, altitudeScale = 5.0, speedScale = 720.0

    /// Start of track log `i`: two logs per 0x10000 block.
    static func trackLogOffset(_ i: Int) -> Int { 0x10000 * (i / 2) + trackLogLength * (i % 2) }

    /// The coordinates of the first track log are plausible (the header lies beyond the detection prefix).
    public func matches(prefix: Data) -> Bool {
        guard prefix.count >= FileFormats.sniffLength else { return false }
        let r = ByteReader(prefix)
        return stride(from: 0, to: FileFormats.sniffLength, by: 8).allSatisfy { o in
            abs(Int(Locosys.i32le(r, o))) <= 180 * 36000 && abs(Int(Locosys.i32le(r, o + 4))) <= 90 * 36000
        }
    }

    public func read(_ inputs: [FileInput]) throws -> ImportResult {
        var recording = Recording()
        var warnings: [ImportWarning] = []
        for input in inputs {
            let result = try Self.read(input)
            recording.tracks += result.recording.tracks
            warnings += result.warnings
        }
        return ImportResult(recording: recording, warnings: warnings)
    }

    /// `trl_read` for one file.
    static func read(_ input: FileInput) throws -> ImportResult {
        let r = ByteReader(input.data)
        guard r.count >= minimumLength, r.u32le(headerOffset) == headerID else {
            throw GPSLoggerError(.malformed(line: nil), fileName: input.name, detail: "Not an Alan Map500 track log (.trl)")
        }
        var warnings = Warnings(fileName: input.name)
        var tracks: [Track] = []
        for i in 0..<maxTracks {
            try Task.checkCancellation()
            let header = headerOffset + 16 + i * trackHeaderLength
            guard r.u32le(header + 32) != 0 else { continue }  // occupied == TRK_UNUSED
            var count = Int(Int16(bitPattern: r.u16le(header) ?? 0))
            if count > maxPoints {
                warnings.add(.malformedRecord, at: nil)  // the source reads beyond the track log
                count = maxPoints
            }
            let log = trackLogOffset(i)
            let points = (0..<max(count, 0)).map { j in point(r, coordinates: log + 8 * j, values: log + maxPoints * 8 + 4 * j) }
            guard !points.isEmpty else { continue }
            let name = text(r, header + 4, length: 12)
            tracks.append(Track(name: name.isEmpty ? trackName(ofFile: input.name) : name, segments: [TrackSegment(points: points)]))
        }
        return ImportResult(recording: Recording(tracks: tracks), warnings: warnings.all)
    }

    /// One point: latitude −y, longitude x (degree · 36000), height (m · 5), speed (m/s · 720, negative = unknown).
    static func point(_ r: ByteReader, coordinates c: Int, values v: Int) -> TrackPoint {
        var quality = PositionQuality()
        let speed = Int16(bitPattern: r.u16le(v) ?? 0)
        if speed >= 0 { quality.speed = Double(speed) / speedScale }
        return TrackPoint(latitude: -Double(Locosys.i32le(r, c + 4)) / pointScale,
                          longitude: Double(Locosys.i32le(r, c)) / pointScale,
                          elevation: Double(Int16(bitPattern: r.u16le(v + 2) ?? 0)) / altitudeScale, quality: quality)
    }

    /// A fixed-length text field without trailing spaces and zero bytes.
    static func text(_ r: ByteReader, _ offset: Int, length: Int) -> String {
        var bytes = (0..<length).compactMap { r.u8(offset + $0) }
        while let last = bytes.last, last == 0x20 || last == 0 { bytes.removeLast() }
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}
