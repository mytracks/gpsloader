// Ported from GPSBabel skytraq.cc (tag gpsbabel_1_7_0), serial download of the format skytraq.
// Original: Copyright (C) 2008-2019 Mathias Adam; 2008 J.C Haessig; 2009-2010 Josef Reisinger.
// Licensed under the GNU General Public License, version 2 or (at your option) any later version.
// Translated to Swift and modified for gpsloader by Dirk Stichling, 2026-11-13.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GPSLoggerKit

/// Reads and erases SkyTraq Venus 5/6 based loggers over a serial connection (spec `skytraq-device`).
public struct SkyTraqDevice: DeviceProtocol {
    /// Baud rate to probe first (`initbaud`); `nil` probes all rates.
    public var initialBaudRate: Int?
    /// Baud rate for the download (`baud`, default 230400).
    public var downloadBaudRate: Int
    /// Time from which the GPS week cycle is chosen.
    var reference: @Sendable () -> Date = { Date() }

    public init(initialBaudRate: Int? = nil, downloadBaudRate: Int = 230_400) {
        self.initialBaudRate = initialBaudRate
        self.downloadBaudRate = downloadBaudRate
    }

    public var eraseSupport: DeviceErase { .supported }

    static let probeRates = [9600, 230_400, 115_200, 57600, 4800, 19200, 38400]
    static let baudCodes: [Int: UInt8] = [4800: 0, 9600: 1, 19200: 2, 38400: 3, 57600: 4, 115_200: 5, 230_400: 6]
    static let timeout: TimeInterval = 5  // TIMEOUT 5000 ms
    static let sectorReadEnd: [UInt8] = Array("END".utf8) + [0] + Array("CHECKSUM=".utf8)
    static let maxReadAtOnce = 255  // read-at-once default

    public func read(_ connection: any DeviceConnection, _ reporter: DeviceReporter) async throws -> Recording {
        let link = SkyTraqLink(connection: connection)
        reporter.step("Connecting")
        let baud = try await link.probe(initial: initialBaudRate)
        let switched = downloadBaudRate != baud
        if switched { try await link.setBaud(downloadBaudRate) }

        let status = try await link.logStatus()
        var sectorsUsed = status.total - status.free + 1
        var dump: [UInt8] = []
        var readAtOnce = Self.maxReadAtOnce
        var multiSupported = true
        var sector = 0
        reading: while sector < sectorsUsed {
            reporter.progress(sector, of: sectorsUsed, step: "Reading memory")
            var got: [UInt8]?
            for _ in 0..<3 {  // SECTOR_RETRIES
                if multiSupported {
                    readAtOnce = max(min(readAtOnce, sectorsUsed - sector), 1)
                    switch try await link.readSectors(first: sector, count: readAtOnce) {
                    case .data(let bytes):
                        got = bytes
                        readAtOnce = min(readAtOnce * 2, Self.maxReadAtOnce)
                    case .nack:
                        multiSupported = false
                    case .failed:
                        readAtOnce = max(readAtOnce / 2, 1)
                    }
                } else if let bytes = try await link.readSingleSector(sector) {
                    got = bytes
                }
                if got != nil { break }
            }
            guard let bytes = got else { throw DeviceProtocolError("Error reading sector \(sector)") }
            let count = bytes.count / SkyTraqDump.sectorSize
            for s in 0..<count {
                let start = s * SkyTraqDump.sectorSize
                let sectorBytes = Array(bytes[start..<(start + SkyTraqDump.sectorSize)])
                let used = SkyTraqDump.usedLength(ofSector: sectorBytes)
                dump += sectorBytes
                if used == 0 {
                    break reading  // stale data after an empty sector
                } else if used >= SkyTraqDump.sectorSize - SkyTraqDump.fullLength, sector + s + 1 >= sectorsUsed,
                          sector + s + 1 < status.total {
                    sectorsUsed += 1
                }
            }
            sector += count
        }
        reporter.progress(sectorsUsed, of: sectorsUsed, step: "Reading memory")

        if switched { try? await link.setBaud(baud) }
        try? await link.restart()

        var decoder = SkyTraqDump(fileName: "SkyTraq", reference: reference())
        try decoder.read(ByteReader(bytes: dump), stopAtPartialSector: false)
        let points = decoder.points
        return Recording(tracks: points.isEmpty ? [] : [Track(name: "SkyTraq", segments: [TrackSegment(points: points)])],
                         waypoints: decoder.waypoints)
    }

    public func erase(_ connection: any DeviceConnection, _ reporter: DeviceReporter) async throws {
        let link = SkyTraqLink(connection: connection)
        reporter.step("Connecting")
        _ = try await link.probe(initial: initialBaudRate)
        reporter.step("Erasing")
        guard try await link.writeVerified([0x19]) == .ok else { throw DeviceProtocolError("Erasing was refused") }
        try? await link.restart()
    }
}

extension SkyTraqDump {
    /// Bytes used by items at the start of a sector (`process_data_sector` without decoding); 0 for an empty sector.
    static func usedLength(ofSector bytes: [UInt8]) -> Int {
        var offset = 0
        while offset < bytes.count, bytes[offset] != 0xFF, let type = ItemType(rawValue: bytes[offset] >> 4),
              offset + type.length <= bytes.count {
            offset += type.length
        }
        return offset
    }
}

/// Message layer of the SkyTraq binary protocol (`skytraq_rd_msg`, `skytraq_wr_msg`, `skytraq_expect_ack`, ...).
struct SkyTraqLink {
    let connection: any DeviceConnection

    enum Ack { case ok, nack, failed }
    enum SectorResult { case data([UInt8]), nack, failed }

    static func checksum(_ bytes: [UInt8]) -> UInt8 { bytes.reduce(0, ^) }

    static func frame(_ payload: [UInt8]) -> [UInt8] {
        [0xA0, 0xA1, UInt8(payload.count >> 8 & 0xFF), UInt8(payload.count & 0xFF)] + payload + [checksum(payload), 0x0D, 0x0A]
    }

    func write(_ payload: [UInt8]) async throws {
        await connection.discardInput()  // rd_drain
        try await connection.write(Self.frame(payload))
    }

    /// Reads one message with at least `minimumLength` payload bytes; `nil` when no valid start or length arrives.
    func readMessage(minimumLength: Int) async throws -> [UInt8]? {
        var state = 0
        for _ in 0..<250 where state < 2 {  // RETRIES
            let c = try await connection.read(count: 1, timeout: SkyTraqDevice.timeout)[0]
            if c == [0xA0, 0xA1][state] {
                state += 1
            } else {
                state = c == 0xA0 ? 1 : 0
            }
        }
        guard state == 2 else { return nil }
        let lengthBytes = try await connection.read(count: 2, timeout: SkyTraqDevice.timeout)
        let length = Int(lengthBytes[0]) << 8 | Int(lengthBytes[1])
        guard length >= minimumLength else { return nil }
        let payload = try await connection.read(count: length, timeout: SkyTraqDevice.timeout + Double(length) / 1000)
        let trailer = try await connection.read(count: 3, timeout: SkyTraqDevice.timeout)
        guard trailer[0] == Self.checksum(payload) else {
            throw DeviceProtocolError("Checksum error: got 0x\(String(trailer[0], radix: 16)), expected 0x\(String(Self.checksum(payload), radix: 16))")
        }
        guard trailer[1] == 0x0D, trailer[2] == 0x0A else { throw DeviceProtocolError("Missing message end (CR/LF)") }
        return payload
    }

    func expectAck(_ id: UInt8) async throws -> Ack {
        for _ in 0..<3 {  // MSG_RETRIES
            guard let message = try await readMessage(minimumLength: 2) else { return .failed }
            if message[0] == 0x83 {
                if message[1] == id { return .ok }
                continue  // some devices first send an ACK with id 0
            } else if message[0] == 0x84 {
                return .nack
            }
        }
        return .failed
    }

    func expectMessage(_ id: UInt8, minimumLength: Int) async throws -> [UInt8]? {
        for _ in 0..<3 {
            guard let message = try await readMessage(minimumLength: minimumLength) else { return nil }
            if message[0] == id { return message }
        }
        return nil
    }

    func writeVerified(_ payload: [UInt8]) async throws -> Ack {
        for _ in 0..<3 {
            try await write(payload)
            let ack = try await expectAckTolerant(payload[0])
            if ack != .failed { return ack }
        }
        return .failed
    }

    /// `expectAck`, but a timeout counts as "no answer" so that the caller can retry.
    private func expectAckTolerant(_ id: UInt8) async throws -> Ack {
        do {
            return try await expectAck(id)
        } catch is DeviceProtocolError {
            throw DeviceProtocolError("Invalid answer to message 0x\(String(id, radix: 16))")
        } catch {
            if error is CancellationError || Task.isCancelled { throw error }
            return .failed
        }
    }

    /// `skytraq_probe`: finds the baud rate the logger answers on.
    func probe(initial: Int?) async throws -> Int {
        let rates = initial.map { [$0] } ?? SkyTraqDevice.probeRates
        for rate in rates {
            await connection.discardInput()
            try await connection.setBaudRate(rate)
            var acknowledged = false
            for _ in 0..<2 {
                try await write([0x02, 0x01])  // query software version
                if try await expectAckTolerant(0x02) == .ok {
                    acknowledged = true
                    break
                }
            }
            guard acknowledged else { continue }
            if (try? await expectMessage(0x80, minimumLength: 14)) ?? nil != nil { return rate }
        }
        throw DeviceProtocolError("No SkyTraq logger found on this port")
    }

    /// `skytraq_set_baud`.
    func setBaud(_ rate: Int) async throws {
        guard let code = SkyTraqDevice.baudCodes[rate] else { throw DeviceProtocolError("Unsupported baud rate \(rate)") }
        guard try await writeVerified([0x05, 0x00, code, 0x02]) == .ok else {
            throw DeviceProtocolError("The logger refused the baud rate \(rate)")
        }
        await connection.discardInput()
        try await connection.setBaudRate(rate)
        try await Task.sleep(nanoseconds: 50_000)  // allow the UART to settle
    }

    /// `skytraq_get_log_buffer_status`.
    func logStatus() async throws -> (writePointer: Int, free: Int, total: Int) {
        guard try await writeVerified([0x17]) == .ok,
              let message = try await expectMessage(0x94, minimumLength: 35) else {
            throw DeviceProtocolError("Can't get log buffer status")
        }
        let r = ByteReader(bytes: message)
        return (Int(r.u32le(1) ?? 0), Int(r.u16le(5) ?? 0), Int(r.u16le(7) ?? 0))
    }

    /// `skytraq_read_multiple_sectors`.
    func readSectors(first: Int, count: Int) async throws -> SectorResult {
        let command: [UInt8] = [0x1D, UInt8(first >> 8 & 0xFF), UInt8(first & 0xFF), UInt8(count >> 8 & 0xFF), UInt8(count & 0xFF)]
        switch try await writeVerified(command) {
        case .nack: return .nack
        case .failed: return .failed
        case .ok: break
        }
        let length = count * SkyTraqDump.sectorSize
        let data = try await connection.read(count: length, timeout: SkyTraqDevice.timeout + Double(length) / 1000)
        let tail = try await connection.read(count: SkyTraqDevice.sectorReadEnd.count + 6, timeout: SkyTraqDevice.timeout)
        guard Array(tail.prefix(SkyTraqDevice.sectorReadEnd.count)) == SkyTraqDevice.sectorReadEnd,
              tail[SkyTraqDevice.sectorReadEnd.count] == Self.checksum(data) else { return .failed }
        return .data(data)
    }

    /// `skytraq_read_single_sector`: data up to "END\0CHECKSUM=", then the checksum; padded to 4096 bytes.
    func readSingleSector(_ sector: Int) async throws -> [UInt8]? {
        guard sector <= 0xFF, try await writeVerified([0x1B, UInt8(sector)]) == .ok else { return nil }
        let data = try await connection.readUntil(SkyTraqDevice.sectorReadEnd,
                                                  maxLength: SkyTraqDump.sectorSize + SkyTraqDevice.sectorReadEnd.count,
                                                  timeout: SkyTraqDevice.timeout)
        let checksum = try await connection.read(count: 1, timeout: SkyTraqDevice.timeout)[0]
        guard data.count <= SkyTraqDump.sectorSize, checksum == Self.checksum(data) else { return nil }
        return data + [UInt8](repeating: 0xFF, count: SkyTraqDump.sectorSize - data.count)
    }

    /// `skytraq_system_restart`.
    func restart() async throws {
        _ = try await writeVerified([0x01, 0x01] + [UInt8](repeating: 0, count: 13))
    }
}
