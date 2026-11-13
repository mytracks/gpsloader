// Ported from GPSBabel magproto.cc (tag gpsbabel_1_7_0), file reader of the formats magellan and magellanx.
// Original: Copyright (C) 2002, 2003, 2004, 2005, 2006, 2007, 2008, 2010 Robert Lipe.
// Licensed under the GNU General Public License, version 2 or (at your option) any later version.
// Translated to Swift and modified for gpsloader by Dirk Stichling, 2026-11-13.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GPSLoggerKit

extension FileFormatID {
    public static let magellan: FileFormatID = "magellan"
}

/// SD card files of Magellan Meridian and eXplorist devices (`.log`, `.upt`, `.rte`), spec `magellan-import`.
///
/// gpsbabel reads `magellan` and `magellanx` files the same way (they differ only when writing), so one
/// format covers both.
public struct MagellanFileFormat: FileFormat {
    public init() {}

    public var id: FileFormatID { .magellan }
    public var displayName: String { L10n.string("format.magellan") }
    public var fileExtensions: [String] { ["log", "upt", "rte"] }

    static let dataTokens = ["$PMGNTRK,", "$PMGNWPL,", "$PMGNRTE,"]

    public func matches(prefix: Data) -> Bool {
        var found = false
        Self.forEachLine(prefix) { _, line in
            if let sentence = MagellanSentences.parse(line), sentence.checksumIsValid,
               Self.dataTokens.contains(where: sentence.starts(with:)) {
                found = true
                return false
            }
            return true
        }
        return found
    }

    public func read(_ inputs: [FileInput]) throws -> ImportResult {
        var recording = Recording()
        var warnings: [ImportWarning] = []
        for input in inputs {
            let result = try Self.read(input)
            recording.tracks += result.recording.tracks
            recording.waypoints += result.recording.waypoints
            warnings += result.warnings
        }
        return ImportResult(recording: recording, warnings: warnings)
    }

    /// `mag_rd_init_common` and `mag_read` for one file.
    static func read(_ input: FileInput) throws -> ImportResult {
        // `extension_hint`: with `-t -w`, waypoint sentences only count in `.upt` files.
        let keepsWaypoints = (input.name as NSString).pathExtension.lowercased() == "upt"
        var points: [TrackPoint] = []
        var waypoints: [Waypoint] = []
        var warnings = Warnings(fileName: input.name)
        var cancellation = Cancellation()
        var failure: Error?
        forEachLine(input.data) { number, line in
            do { try cancellation.tick() } catch { failure = error; return false }
            guard line.contains(where: { !$0.isWhitespace }) else { return true }
            guard let sentence = MagellanSentences.parse(line) else {
                // The source stops at a line without `$`; skipping it keeps the rest of the file.
                if line.first != "$" { warnings.add(.malformedRecord, at: number) }
                return true
            }
            if !sentence.checksumIsValid { warnings.add(.checksumMismatch, at: number) }
            if sentence.starts(with: "$PMGNTRK,") {
                points.append(MagellanSentences.trackPoint(sentence.text))
            } else if sentence.starts(with: "$PMGNWPL,") {
                if keepsWaypoints { waypoints.append(MagellanSentences.waypoint(sentence.text)) }
            } else if sentence.starts(with: "$PMGNCMD,END") {
                return false
            }
            return true
        }
        if let failure { throw failure }
        let tracks = points.isEmpty ? [] : [Track(name: trackName(ofFile: input.name), segments: [TrackSegment(points: points)])]
        return ImportResult(recording: Recording(tracks: tracks, waypoints: waypoints), warnings: warnings.all)
    }

    /// Calls `body` with each line (number from 1, without CR/LF) until it returns `false`.
    static func forEachLine(_ data: Data, _ body: (Int, Substring) -> Bool) {
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            let bytes = buffer.bindMemory(to: UInt8.self)
            var start = 0
            var number = 1
            while start < bytes.count {
                var end = start
                while end < bytes.count, bytes[end] != 0x0A { end += 1 }
                var last = end
                while last > start, bytes[last - 1] == 0x0D { last -= 1 }
                let text = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<last]), as: UTF8.self)
                if !body(number, Substring(text)) { return }
                number += 1
                start = end + 1
            }
        }
    }
}
