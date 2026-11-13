// i-GotU loggers (change igotu-driver). Based on:
//   - the author's own myTracks driver IGotUGT800.m (Copyright (c) 2013 Dirk Stichling), git history of myTracks;
//   - igotu2gpx 0.3.0 by Michael Hofmann (src/igotu/igotucommand.cpp, commands.cpp, igotucontrol.cpp, HACKING),
//     Copyright (C) 2009 Michael Hofmann, licensed under the GNU General Public License, version 3 or
//     (at your option) any later version.
// Translated to Swift and modified for gpsloader by Dirk Stichling, 2026-11-13.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GPSLoggerKit

/// Reads and (experimentally) erases i-GotU loggers (spec `igotu-device`): the GT-800/GT-800 Pro over a serial
/// port, the GT-100/120/200/200e/600 over USB HID.
public struct IGotUDevice: DeviceProtocol {
    public enum Variant: Sendable, Equatable {
        /// GT-800 and GT-800 Pro: serial at 9600 baud, a command is sent as one 16-byte block.
        case serial
        /// USB models: a command is sent in 8-byte chunks, each answered with a response header.
        case hid
    }

    public var variant: Variant
    /// Time from which the year (stored modulo 16) is reconstructed.
    var reference: @Sendable () -> Date = { Date() }

    public init(variant: Variant) {
        self.variant = variant
    }

    public static let serialBaudRate = 9600
    public static let usbVendorID = 0x0DF7
    public static let usbProductIDs = [0x0900]

    /// Not verified with hardware; the commands are undocumented.
    public var eraseSupport: DeviceErase { .experimental }

    static let blockSize = 0x1000
    static let recordLength = 0x20

    public func read(_ connection: any DeviceConnection, _ reporter: DeviceReporter) async throws -> Recording {
        let link = IGotULink(connection: connection, variant: variant)
        reporter.step("Connecting")
        _ = try await link.send([0x93, 0x01, 0x01, 0x03])  // NMEA switch: configure mode (no NMEA)
        if variant == .hid { _ = try await link.send([0x93, 0x0A]) }  // identification
        let count = try await link.count()
        let blocks = (count * Self.recordLength + Self.blockSize - 1) / Self.blockSize
        var data: [UInt8] = []
        for i in 0..<blocks {
            reporter.progress(i, of: blocks, step: "Reading memory")
            data += try await link.read(position: (i + 1) * Self.blockSize, size: Self.blockSize)
        }
        reporter.progress(blocks, of: max(blocks, 1), step: "Reading memory")
        _ = try? await link.send([0x93, 0x01, 0x01, 0x00], ignoreErrors: true)  // back to NMEA mode
        return Self.decode(data, count: count, variant: variant, reference: reference())
    }

    public func erase(_ connection: any DeviceConnection, _ reporter: DeviceReporter) async throws {
        let link = IGotULink(connection: connection, variant: variant)
        reporter.step("Connecting")
        _ = try await link.send([0x93, 0x01, 0x01, 0x03])
        reporter.step("Erasing")
        switch variant {
        case .serial:
            _ = try await link.send([0x93, 0x05, 0x04, 0x00, 0x03, 0x01, 0x9F])  // model
            try await link.purge(blocks: 0x700, reporter: reporter, wait: { try await link.waitForWrite(maximum: nil) })
        case .hid:
            let identification = try await link.send([0x93, 0x0A])
            let firmware = identification.count >= 6 ? Int(identification[4]) << 8 | Int(identification[5]) : 0
            let model = try await link.send([0x93, 0x05, 0x04, 0x00, 0x03, 0x01, 0x9F])
            let blocks: Int
            switch (model.count >= 3 && model[0] == 0xC2 && model[1] == 0x20) ? model[2] : 0 {
            case 0x13: blocks = 0x080  // GT-100
            case 0x15: blocks = 0x200  // GT-120
            case 0x14: blocks = 0x100  // GT-200
            default: throw DeviceProtocolError("Erasing is not supported for this i-GotU model")
            }
            let purged = try await link.purge(blocks: blocks, reporter: reporter,
                                              wait: { try await link.waitForWrite(maximum: 10) })
            if firmware >= 0x0215 {
                if purged {
                    _ = try await link.send([0x93, 0x0C, 0x00, 0x1E])
                    _ = try await link.send([0x93, 0x0C, 0x00, 0x1F])
                    try await link.waitForWrite(maximum: 10)
                }
                _ = try await link.send([0x93, 0x0C, 0x00, 0x1E])
                _ = try await link.send([0x93, 0x0C, 0x00, 0x1F])
            } else {
                if purged {
                    _ = try await link.send([0x93, 0x08, 0x02])
                    try await link.waitForWrite(maximum: 10)
                }
                _ = try await link.send([0x93, 0x08, 0x02])
            }
        }
        _ = try? await link.send([0x93, 0x01, 0x01, 0x00], ignoreErrors: true)
    }

    /// Decodes `count` records of 32 bytes (`createTrackPoints` of IGotUGT800.m).
    static func decode(_ data: [UInt8], count: Int, variant: Variant, reference: Date) -> Recording {
        let r = ByteReader(bytes: data)
        let currentYear = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: reference).year ?? 2026
        var tracks: [[TrackPoint]] = [[]]
        var waypoints: [Waypoint] = []
        var newTrack = false
        for k in 0..<min(count, data.count / recordLength) {
            let o = k * recordLength
            let flags = r.u8(o) ?? 0
            if flags == 0xF1 { continue }  // debug record with ASCII text
            if flags & 0x40 != 0, !(tracks.last?.isEmpty ?? true) { newTrack = true }
            let satellites = Int((r.u8(o + 0x1D) ?? 0) & 0x0F)
            let maximumSV = Int((r.u8(o + 0x1D) ?? 0) >> 4)
            let valid = flags & 0x10 == 0 && (variant == .serial ? satellites > 4 && maximumSV > 0 : satellites > 0)
            guard valid, let time = time(r, o, currentYear: currentYear) else { continue }
            if newTrack {
                tracks.append([])
                newTrack = false
            }
            var quality = PositionQuality()
            quality.satellites = satellites
            let point = TrackPoint(latitude: Double(Int32(bitPattern: r.u32be(o + 0x0C) ?? 0)) / 1e7,
                                   longitude: Double(Int32(bitPattern: r.u32be(o + 0x10) ?? 0)) / 1e7,
                                   elevation: Double(Int32(bitPattern: r.u32be(o + 0x14) ?? 0)) / 100,
                                   time: time, quality: quality)
            tracks[tracks.count - 1].append(point)
            if flags & 0x04 != 0 {
                waypoints.append(Waypoint(latitude: point.latitude, longitude: point.longitude, elevation: point.elevation,
                                          time: time, name: "POI \(waypoints.count + 1)", quality: quality))
            }
        }
        let nonEmpty = tracks.filter { !$0.isEmpty }
        return Recording(tracks: nonEmpty.enumerated().map { index, points in
            Track(name: nonEmpty.count == 1 ? "i-GotU" : "i-GotU (\(index + 1))", segments: [TrackSegment(points: points)])
        }, waypoints: waypoints)
    }

    /// Year modulo 16 in the high nibble of byte 1 (the latest matching year up to `currentYear`), month,
    /// day, hour, minute and milliseconds of the minute (UTC).
    static func time(_ r: ByteReader, _ o: Int, currentYear: Int) -> Date? {
        let b1 = Int(r.u8(o + 1) ?? 0), b2 = Int(r.u8(o + 2) ?? 0), b3 = Int(r.u8(o + 3) ?? 0)
        let yearMod16 = b1 >> 4 & 0x0F
        let year = currentYear % 16 >= yearMod16 ? currentYear - currentYear % 16 + yearMod16
                                                 : currentYear - 16 - currentYear % 16 + yearMod16
        let milliseconds = Int(r.u16be(o + 4) ?? 0)
        return Locosys.utc(year: year, month: b1 & 0x0F, day: b2 >> 3 & 0x1F, hour: (b2 & 0x07) * 4 + (b3 >> 6 & 0x03),
                           minute: b3 & 0x3F, second: Double(milliseconds) / 1000)
    }
}

/// Command layer (`IgotuCommand::sendAndReceive`, `sendCommandWithChunk:` of IGotUGT800.m).
struct IGotULink {
    let connection: any DeviceConnection
    let variant: IGotUDevice.Variant
    static let timeout: TimeInterval = 5

    /// The command padded to 16 bytes with the checksum in the last byte (sum of all bytes is zero).
    static func frame(_ command: [UInt8]) -> [UInt8] {
        var bytes = command + [UInt8](repeating: 0, count: max(0, 16 - command.count))
        bytes[15] = 0
        bytes[15] = 0 &- bytes.reduce(0, &+)
        return bytes
    }

    /// Reads the response header `93 SS SS` (bytes before 0x93 are dropped) and returns the signed size.
    func responseSize() async throws -> Int {
        var skipped = 0
        while try await connection.read(count: 1, timeout: Self.timeout)[0] != 0x93 {
            skipped += 1
            if skipped > 4096 { throw DeviceProtocolError("No response from the i-GotU") }
        }
        let size = try await connection.read(count: 2, timeout: Self.timeout)
        return Int(Int16(bitPattern: UInt16(size[0]) << 8 | UInt16(size[1])))
    }

    /// Sends a command and returns the response data; retries device errors three times and protocol errors
    /// five times, as igotu2gpx.
    @discardableResult
    func send(_ command: [UInt8], ignoreErrors: Bool = false) async throws -> [UInt8] {
        let bytes = Self.frame(command)
        var protocolErrors = 0, deviceErrors = 0
        while true {
            do {
                var size = 0
                switch variant {
                case .serial:
                    await connection.discardInput()
                    try await connection.write(bytes)
                    size = try await responseSize()
                case .hid:
                    for piece in 0..<2 {
                        await connection.discardInput()
                        try await connection.write(Array(bytes[(piece * 8)..<(piece * 8 + 8)]))
                        size = try await responseSize()
                        if size < 0 { break }
                        if size != 0, piece == 0 { throw DeviceProtocolError("Non-empty intermediate response") }
                    }
                }
                if size < 0 {
                    deviceErrors += 1
                    if deviceErrors <= 3 { continue }
                    throw DeviceProtocolError("The i-GotU responded with error code \(size)")
                }
                return size > 0 ? try await connection.read(count: size, timeout: Self.timeout + Double(size) / 1000) : []
            } catch let error as DeviceProtocolError {
                if ignoreErrors { return [] }
                protocolErrors += 1
                if protocolErrors <= 5 { continue }
                throw error
            }
        }
    }

    /// Number of records (`CountCommand`; the GT-800 uses two more bits of the first byte).
    func count() async throws -> Int {
        let response = try await send([0x93, 0x0B, 0x03, 0x00, 0x1D])
        guard response.count >= 3 else { throw DeviceProtocolError("Count response too short") }
        let low = Int(response[1]) << 8 | Int(response[2])
        return variant == .serial ? Int(response[0] & 0x03) << 16 + low : low
    }

    /// `ReadCommand`: `size` bytes from flash position `position`.
    func read(position: Int, size: Int) async throws -> [UInt8] {
        let data = try await send([0x93, 0x05, 0x07, UInt8(size >> 8 & 0xFF), UInt8(size & 0xFF), 0x04, 0x03,
                                   UInt8(position >> 16 & 0xFF), UInt8(position >> 8 & 0xFF), UInt8(position & 0xFF)])
        guard data.count == size else { throw DeviceProtocolError("Read \(data.count) instead of \(size) bytes") }
        return data
    }

    /// `UnknownWriteCommand2(0x0001)` until it answers 0x00.
    func waitForWrite(maximum: Int?) async throws {
        var tries = 0
        while true {
            let response = try await send([0x93, 0x05, 0x04, 0x00, 0x01, 0x01, 0x05])
            if response.first == 0x00 { return }
            tries += 1
            if let maximum, tries >= maximum { throw DeviceProtocolError("The i-GotU did not finish erasing") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// Purges all used blocks from the end of the flash downwards (`purgeMemory` of IGotUGT800.m and
    /// `IgotuControlPrivateWorker::purge`); returns whether anything was purged.
    @discardableResult
    func purge(blocks: Int, reporter: DeviceReporter, wait: () async throws -> Void) async throws -> Bool {
        var purging = false
        var i = blocks - 1
        while i > 0 {
            try Task.checkCancellation()
            if purging {
                try await wait()
            } else if try await read(position: i * IGotUDevice.blockSize, size: 0x10) != [UInt8](repeating: 0xFF, count: 0x10) {
                purging = true
            } else {
                i -= 1
                continue
            }
            reporter.progress(blocks - i, of: blocks, step: "Erasing")
            _ = try await send([0x93, 0x06, 0x04, 0x00, 0x00, 0x01, 0x06])  // UnknownWriteCommand1(0x00)
            let position = i * IGotUDevice.blockSize
            _ = try await send([0x93, 0x06, 0x07, 0x00, 0x00, 0x04, 0x20,  // WriteCommand(0x20, position)
                                UInt8(position >> 16 & 0xFF), UInt8(position >> 8 & 0xFF), UInt8(position & 0xFF)])
            i -= 1
        }
        if purging, variant == .serial { try await wait() }
        return purging
    }
}
