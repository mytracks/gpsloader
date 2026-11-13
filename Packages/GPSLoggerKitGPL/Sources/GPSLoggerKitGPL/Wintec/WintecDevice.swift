// Ported from GPSBabel wbt-200.cc (tag gpsbabel_1_7_0), serial download of the format wbt.
// Original: Copyright (C) 2006 Andy Armstrong.
// Licensed under the GNU General Public License, version 2 or (at your option) any later version.
// Translated to Swift and modified for gpsloader by Dirk Stichling, 2026-11-13.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GPSLoggerKit

/// Reads and erases Wintec WBT-100/200/201, G-Rays 2 and WSG-1000 loggers over a serial connection
/// (spec `wintec-device`). The device type is detected like in the source.
public struct WintecDevice: DeviceProtocol {
    public enum DeviceType: Sendable, Equatable {
        case wbt200, wbt201, wsg1000
    }

    public init() {}

    public var eraseSupport: DeviceErase { .supported }

    public static let wbt200Baud = 9600
    public static let wbt201Baud = 57600
    static let chunkSize = 4096  // WBT201CHUNK
    static let timeout: TimeInterval = 5  // TIMEOUT 5000 ms

    public func read(_ connection: any DeviceConnection, _ reporter: DeviceReporter) async throws -> Recording {
        let link = WintecLink(connection: connection, reporter: reporter)
        reporter.step("Connecting")
        let type = try await link.guessDevice()
        var result = WintecResult()
        var warnings = Warnings(fileName: "Wintec")
        switch type {
        case .wbt200:
            try await link.readWBT200(into: &result)
        case .wbt201, .wsg1000:
            try await link.readWBT201(type: type, into: &result, warnings: &warnings)
        }
        var recording = Recording()
        result.append(to: &recording, fileName: "Wintec")
        return recording
    }

    public func erase(_ connection: any DeviceConnection, _ reporter: DeviceReporter) async throws {
        let link = WintecLink(connection: connection, reporter: reporter)
        reporter.step("Connecting")
        let type = try await link.guessDevice()
        reporter.step("Erasing")
        switch type {
        case .wbt200:
            for file in 27...31 {
                _ = try await link.command("$PFST,REMOVEFILE,\(file)", expect: "$PFST,REMOVEFILE")
            }
            for area in 0...3 {
                _ = try await link.command("$PFST,FFSRECLAIM,\(area)", expect: "$PFST,FFSRECLAIM")
            }
            _ = try await link.command("$PFST,NORMAL", expect: "$PFST,NORMAL")
        case .wbt201, .wsg1000:
            _ = try await link.command("@AL,5,6", expect: "@AL,5,6")
            _ = try await link.command("@AL,2,1", expect: "@AL,2,1")
        }
    }
}

/// Text and binary layer of the Wintec protocols (`expect`, `do_cmd`, `get_param`, `wbt*_data_read`, ...).
struct WintecLink {
    let connection: any DeviceConnection
    let reporter: DeviceReporter

    func send(_ command: String) async throws {
        try await connection.write(Array((command + "\r\n").utf8))
    }

    /// `expect`: waits for `text` in the incoming bytes (at most 5000 bytes, 5 timeouts of 0.5 s).
    func expect(_ text: String) async throws -> Bool {
        let pattern = Array(text.utf8)
        var state = 0
        var errors = 5
        for _ in 0..<5000 {
            if state == pattern.count { return true }
            do {
                let c = try await connection.read(count: 1, timeout: 0.5)[0]
                state = c == pattern[state] ? state + 1 : 0
            } catch {
                if error is CancellationError || Task.isCancelled { throw error }
                errors -= 1
                if errors <= 0 { return false }
            }
        }
        return state == pattern.count
    }

    /// `guess_device`: tries WBT-200 (9600 baud), WBT-201 and WSG-1000 (57600 baud), five rounds.
    func guessDevice() async throws -> WintecDevice.DeviceType {
        for _ in 0..<5 {
            try await connection.setBaudRate(WintecDevice.wbt200Baud)
            try await send("$PFST,NORMAL")
            if try await expect("$PFST") { return .wbt200 }
            try await connection.setBaudRate(WintecDevice.wbt201Baud)
            try await send("@AL")
            if try await expect("@AL") { return .wbt201 }
            try await connection.setBaudRate(WintecDevice.wbt201Baud)
            try await send("@AL,2,3")
            if try await expect("@AL,2,3,OK") { return .wsg1000 }
        }
        throw DeviceProtocolError("Can't determine the Wintec device type")
    }

    /// One line (LF terminated, CR removed).
    func line() async throws -> String {
        let bytes = try await connection.readUntil([0x0A], maxLength: 4096, timeout: WintecDevice.timeout)
        return String(decoding: bytes.filter { $0 != 0x0D }, as: UTF8.self)
    }

    /// `do_cmd`: sends `command`, then reads up to 60 lines until one starts with `expect`; returns that line.
    func command(_ command: String, expect: String) async throws -> String {
        await connection.discardInput()
        try await send(command)
        for _ in 0..<60 {  // RETRIES; the unit streams NMEA data all the time
            let text = try await line()
            reporter.activity()
            if text.hasPrefix(expect) { return text }
        }
        throw DeviceProtocolError("Bad response from the unit to \(command)")
    }

    /// `get_param`: the value after the echoed command and one separator.
    func parameter(_ command: String) async throws -> String {
        let text = try await self.command(command, expect: command)
        return String(text.dropFirst(command.count + 1))
    }

    // MARK: WBT-100/200

    /// `wbt200_data_read`: 6-byte header with the point count, then raw records of 12 or 16 bytes.
    func readWBT200(into result: inout WintecResult) async throws {
        _ = try await command("$PFST,FIRMWAREVERSION", expect: "$PFST,FIRMWAREVERSION")
        _ = try await command("$PFST,NORMAL", expect: "$PFST,NORMAL")
        _ = try await command("$PFST,READLOGGER", expect: "$PFST,READLOGGER")
        let header = try await connection.read(count: 6, timeout: WintecDevice.timeout)
        var count = (Int(header[2]) | Int(header[3]) << 8) + 1
        if count == 0x10000 { count = 0 }

        var data: [UInt8] = []
        var chosen: Int?
        for length in WintecLog.recordLengths {  // ascending, reading more data for each format
            let want = length * count
            while data.count < want {
                let chunk = min(512, want - data.count)
                data += try await connection.read(count: chunk, timeout: WintecDevice.timeout)
                reporter.progress(data.count, of: WintecLog.recordLengths.last! * count, step: "Reading memory")
            }
            if WintecLog.isValid(ByteReader(bytes: Array(data.prefix(want))), length: length) {
                chosen = length
                data = Array(data.prefix(want))
                break
            }
        }
        guard let length = chosen else { throw DeviceProtocolError("Can't detect the data format") }
        try WintecLog.readBin(ByteReader(bytes: data), length: length, into: &result)
        _ = try? await command("$PFST,NORMAL", expect: "$PFST,NORMAL")
    }

    // MARK: WBT-201, G-Rays 2, WSG-1000

    /// `wbt201_data_read`: reads the log area in chunks of 4 KiB, wrapping around the ring buffer.
    func readWBT201(type: WintecDevice.DeviceType, into result: inout WintecResult, warnings: inout Warnings) async throws {
        _ = try await parameter("@AL,7,1")
        _ = try await parameter("@AL,8,1")
        _ = try await parameter("@AL,8,2")
        _ = try await parameter("@AL,8,3")
        guard let start = Int(try await parameter("@AL,5,1")), let end = Int(try await parameter("@AL,5,2")),
              let areaStart = Int(try await parameter("@AL,5,9")), let areaEnd = Int(try await parameter("@AL,5,10"))
        else { throw DeviceProtocolError("Invalid log addresses") }

        let total = start < end ? end - start : areaEnd - (start - end)
        var remaining = total
        var pointer = start
        var limit = start < end ? end : areaEnd
        var tries = 10
        while remaining > 0 {
            reporter.progress(total - remaining, of: total, step: "Reading memory")
            if let chunk = try await readChunk(position: pointer, limit: limit, type: type) {
                _ = try WintecLog.readWBT201Records(ByteReader(bytes: chunk), from: 0, into: &result, warnings: &warnings)
                remaining -= chunk.count
                pointer += chunk.count
                if pointer >= areaEnd {
                    pointer = areaStart
                    limit = end
                }
            } else {
                tries -= 1
                if tries == 0 { throw DeviceProtocolError("Too many data errors during the download") }
            }
        }
        reporter.progress(total, of: max(total, 1), step: "Reading memory")
        _ = try? await command("@AL,2,1", expect: "@AL,2,1")
    }

    /// `wbt201_read_chunk`: `@AL,5,3,<pos>`, raw data, `@AL,CS,<xor hex>,…` and (WBT-201) the echoed command.
    func readChunk(position: Int, limit: Int, type: WintecDevice.DeviceType) async throws -> [UInt8]? {
        let want = min(limit - position, WintecDevice.chunkSize)
        await connection.discardInput()
        let command = "@AL,5,3,\(position)"
        try await send(command)
        guard let data = try? await connection.read(count: want, timeout: WintecDevice.timeout) else { return nil }
        reporter.activity()
        let checksumLine = try await line()
        let prefix = "@AL,CS,"
        guard checksumLine.hasPrefix(prefix) else { return nil }
        let fields = checksumLine.dropFirst(prefix.count).split(separator: ",", omittingEmptySubsequences: false)
        guard fields.count >= 2, let checksum = UInt8(fields[0], radix: 16), checksum == data.reduce(0, ^) else { return nil }
        if type == .wbt201 {
            guard try await line().hasPrefix(command) else { return nil }
        }
        return data
    }
}
