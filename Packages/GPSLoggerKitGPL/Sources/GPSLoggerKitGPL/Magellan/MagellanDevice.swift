// Ported from GPSBabel magproto.cc (tag gpsbabel_1_7_0), serial download of the format magellan.
// Original: Copyright (C) 2002, 2003, 2004, 2005, 2006, 2007, 2008, 2010 Robert Lipe.
// Licensed under the GNU General Public License, version 2 or (at your option) any later version.
// Translated to Swift and modified for gpsloader by Dirk Stichling, 2026-11-13.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GPSLoggerKit

/// Reads the track log and the waypoints of Magellan Meridian and SporTrak devices over a serial connection
/// (spec `magellan-device`). Like the source when reading, no acknowledgements are exchanged.
public struct MagellanDevice: DeviceProtocol {
    public init() {}

    /// Default of the source's option `baud`.
    public static let baudRate = 4800
    /// `gbser_read_line(…, 2000, 0x0a, 0x0d)` in `termread`.
    static let lineTimeout: TimeInterval = 2
    /// `mag_serial_init_common`: the GPS 315 takes up to 4.25 s to answer.
    static let versionTimeout: TimeInterval = 6
    static let trackName = "Magellan"

    public func read(_ connection: any DeviceConnection, _ reporter: DeviceReporter) async throws -> Recording {
        let link = MagellanLink(connection: connection, reporter: reporter)
        do {
            let recording = try await download(link, reporter)
            try await link.send("PMGNCMD,HANDOFF")
            return recording
        } catch {
            try? await link.send("PMGNCMD,HANDOFF")  // `mag_deinit`
            throw error
        }
    }

    private func download(_ link: MagellanLink, _ reporter: DeviceReporter) async throws -> Recording {
        reporter.step("Connecting")
        _ = try await link.connect()

        // `mag_read`, track part.
        reporter.step("Reading track")
        await link.connection.discardInput()
        try await link.send("PMGNCMD,TRACK,2")
        var points: [TrackPoint] = []
        let trackComplete = try await link.receive { sentence in
            if sentence.starts(with: "$PMGNTRK,") { points.append(MagellanSentences.trackPoint(sentence.text)) }
        }
        if !trackComplete { reporter.step("The device sends no track") }

        // Waypoint part.
        reporter.step("Reading waypoints")
        try await link.send("PMGNCMD,WAYPOINT")
        var waypoints: [Waypoint] = []
        let waypointsComplete = try await link.receive { sentence in
            if sentence.starts(with: "$PMGNWPL,") { waypoints.append(MagellanSentences.waypoint(sentence.text)) }
        }
        if !waypointsComplete { reporter.step("The device sends no waypoints") }
        let tracks = points.isEmpty ? [] : [Track(name: Self.trackName, segments: [TrackSegment(points: points)])]
        return Recording(tracks: tracks, waypoints: waypoints)
    }
}

/// Line layer of the Magellan protocol (`termread`, `termwrite`, `mag_writemsg` without acknowledgements).
struct MagellanLink {
    let connection: any DeviceConnection
    let reporter: DeviceReporter

    func send(_ body: String) async throws {
        try await connection.write(MagellanSentences.command(body))
    }

    /// One line up to LF, without CR (`gbser_read_line(…, 0x0a, 0x0d)`).
    func line(timeout: TimeInterval = MagellanDevice.lineTimeout) async throws -> String {
        let bytes = try await connection.readUntil([0x0A], maxLength: 512, timeout: timeout)
        return String(decoding: bytes.filter { $0 != 0x0D }, as: UTF8.self)
    }

    /// `mag_serial_init_common` for reading: `HANDOFF`, `VERSION`, wait for `$PMGNVER`, then `NMEAOFF`.
    func connect() async throws -> MagellanSentences.Model {
        try await send("PMGNCMD,HANDOFF")
        await connection.discardInput()
        try await send("PMGNCMD,VERSION")
        let deadline = Date().addingTimeInterval(MagellanDevice.versionTimeout)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw DeviceProtocolError("No acknowledgment from the GPS") }
            // Lines without `$` (e.g. the rest of an NMEA sentence) are skipped; the source stops there.
            if let sentence = MagellanSentences.parse(try await line(timeout: min(MagellanDevice.lineTimeout, remaining))) {
                guard sentence.checksumIsValid else {
                    throw DeviceProtocolError("Bad communication. Check the baud rate.")
                }
                if sentence.starts(with: "$PMGNVER,") {
                    let model = try Self.model(sentence.text)
                    if model.understandsNMEAOff { try await send("PMGNCMD,NMEAOFF") }
                    return model
                }
            }
        }
    }

    /// `mag_verparse`.
    static func model(_ text: String) throws -> MagellanSentences.Model {
        let fields = MagellanSentences.fields(text)
        let productID = fields.count > 1 ? MagellanSentences.leadingInteger(fields[1]) ?? 0 : 0
        let version = fields.count > 2 ? String(fields[2].prefix { $0 != "*" }) : ""
        guard let entry = MagellanSentences.Model.forProductID(productID) else {
            throw DeviceProtocolError("Unknown receiver type \(productID), model version '\(version)'")
        }
        return entry.model
    }

    /// `mag_readmsg` in a loop until `$PMGNCMD,END` (returns `true`) or `$PMGNCMD,UNABLE` (returns `false`).
    func receive(_ handle: (MagellanSentences.Received) -> Void) async throws -> Bool {
        while true {
            guard let sentence = MagellanSentences.parse(try await line()) else { continue }
            reporter.activity()
            if sentence.starts(with: "$PMGNCMD,UNABLE") { return false }
            if sentence.starts(with: "$PMGNCMD,END") { return true }
            handle(sentence)
        }
    }
}
