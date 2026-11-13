// Ported from GPSBabel mtk_logger.cc (tag gpsbabel_1_7_0), serial download of the formats mtk and m241.
// Original: Copyright (C) 2007 Per Borgentun; with inspiration from wbt-200.c, Copyright (C) 2006 Andy Armstrong.
// Licensed under the GNU General Public License, version 2 or (at your option) any later version.
// Translated to Swift and modified for gpsloader by Dirk Stichling, 2026-11-13.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GPSLoggerKit

/// Reads and erases MTK based loggers (iBlue 747, Qstarz, Holux M-241/GPSport 245) over a serial
/// connection (spec `mtk-device`).
public struct MTKDevice: DeviceProtocol {
    public enum Model: Sendable, Equatable {
        /// MTK loggers at 115200 baud.
        case mtk
        /// Holux M-241 and GPSport 245 at 38400 baud.
        case holux
    }

    public var model: Model

    public init(model: Model) {
        self.model = model
    }

    public var eraseSupport: DeviceErase { .supported }

    public var baudRate: Int { model == .mtk ? 115_200 : 38400 }

    static let lineTimeout: TimeInterval = 1.5  // TIMEOUT 1500 ms
    static let blockSize = 1024  // block_size_kb default 1
    static let logStatus = "$PMTK182,2,7*3C\r\n"
    static let logDisable = "$PMTK182,5*20\r\n"
    static let logEnable = "$PMTK182,4*21\r\n"
    static let logFormat = "$PMTK182,2,2*39\r\n"
    static let logErase = "$PMTK182,6,1*3E\r\n"

    /// `$` + body + `*` + XOR checksum (hex) + CR LF.
    static func sentence(_ body: String) -> String {
        let checksum = body.utf8.reduce(UInt8(0), ^)
        return "$" + body + "*" + String(format: "%02X", checksum) + "\r\n"
    }

    public func read(_ connection: any DeviceConnection, _ reporter: DeviceReporter) async throws -> Recording {
        let link = MTKLink(connection: connection, reporter: reporter)
        reporter.step("Connecting")
        let gr245 = try await link.identify()
        let logEnabled = (Int(try await link.command(Self.logStatus, expect: "PMTK182,3,7,", seconds: 2) ?? "") ?? 0) & 2 != 0
        try await Task.sleep(nanoseconds: 10_000_000)
        _ = try await link.command(Self.logDisable, expect: "PMTK001,182,5,3", seconds: 2)
        try await Task.sleep(nanoseconds: 100_000_000)

        var addressMax = 0
        var scan = false
        if let usage = try await link.command("$PMTK182,2,8*33\r\n", expect: "PMTK182,3,8,", seconds: 2),
           let value = Int(usage, radix: 16), value > 0 {
            addressMax = value - value % 65536 + 65535
        }
        if addressMax == 0 {  // flash usage unknown: find the first empty 64 KiB block
            addressMax = 0x200000
            scan = true
        }

        var dump: [UInt8] = []
        if scan {
            var address = 0
            while address < addressMax {
                let block = try await link.readBlock(address: address, size: 0x400)
                if block.allFF {
                    addressMax = address
                    break
                }
                address += 0x10000
            }
        }
        var address = 0
        while address < addressMax {
            reporter.progress(address, of: addressMax, step: "Reading memory")
            let block = try await link.readBlock(address: address, size: Self.blockSize)
            if block.allFF {  // read complete
                addressMax = address
                break
            }
            dump += block.bytes
            address += block.bytes.count
        }
        reporter.progress(addressMax, of: max(addressMax, 1), step: "Reading memory")

        if logEnabled { _ = try? await link.command(Self.logEnable, expect: "PMTK001,182,4,3", seconds: 2) }
        if gr245 { _ = try? await link.command("$PHLX827*31\r\n", expect: "PHLX860*32", seconds: 10) }

        guard !dump.isEmpty else { return Recording() }
        let result = try MTKDump.read([FileInput(name: model == .mtk ? "MTK" : "Holux", data: Data(dump))],
                                      device: model == .mtk ? .mtk : .holuxM241)
        return result.recording
    }

    public func erase(_ connection: any DeviceConnection, _ reporter: DeviceReporter) async throws {
        let link = MTKLink(connection: connection, reporter: reporter)
        reporter.step("Connecting")
        let gr245 = try await link.identify()
        reporter.step("Erasing")
        let status = Int(try await link.command(Self.logStatus, expect: "PMTK182,3,7,", seconds: 2) ?? "") ?? 0
        _ = try await link.command(Self.logFormat, expect: "PMTK182,3,2,", seconds: 2)
        _ = try await link.command(Self.logDisable, expect: "PMTK001,182,5,3", seconds: 1)
        try await Task.sleep(nanoseconds: 10_000_000)
        guard try await link.command(Self.logErase, expect: "PMTK001,182,6", seconds: 30, isErase: true) != nil else {
            throw DeviceProtocolError("The logger did not confirm erasing")
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        if status & 2 != 0 { _ = try? await link.command(Self.logEnable, expect: "PMTK001,182,4,3", seconds: 2) }
        if gr245 { _ = try? await link.command("$PHLX827*31\r\n", expect: "PHLX860*32", seconds: 10) }
    }
}

/// The NMEA-like command layer of MTK loggers (`do_cmd`, the block loop of `mtk_read`).
struct MTKLink {
    let connection: any DeviceConnection
    let reporter: DeviceReporter

    struct Block {
        var bytes: [UInt8]
        var allFF: Bool { !bytes.isEmpty && bytes.allSatisfy { $0 == 0xFF } }
    }

    /// One line (LF terminated, CR removed); `nil` on timeout.
    func line() async throws -> String? {
        do {
            let bytes = try await connection.readUntil([0x0A], maxLength: 4096, timeout: MTKDevice.lineTimeout)
            return String(decoding: bytes.filter { $0 != 0x0D }, as: UTF8.self)
        } catch is DeviceProtocolError {
            throw DeviceProtocolError("Line too long")
        } catch {
            if error is CancellationError || Task.isCancelled { throw error }
            return nil
        }
    }

    /// `do_cmd`: sends `command` and waits up to `seconds` for a line `$<expect>…`. Returns the text after
    /// `expect` without the checksum (empty when there is none), or `nil` when the logger did not answer in
    /// time or rejected the command (`$PMTK001,<type>,<sub>,<flag>` with flag 0, 1 or 2).
    func command(_ command: String, expect: String, seconds: TimeInterval, isErase: Bool = false) async throws -> String? {
        try await connection.write(Array(command.utf8))
        let deadline = Date().addingTimeInterval(seconds)
        let commandFields = command.dropFirst(5).prefix { $0 != "*" }.split(separator: ",", omittingEmptySubsequences: false)
        while Date() < deadline {
            reporter.activity()
            guard let text = try await line() else { continue }
            guard text.count > 5, text.first == "$" else { continue }
            let body = text.dropFirst()
            if body.hasPrefix(expect) {
                var rest = body.dropFirst(expect.count)
                if let star = rest.lastIndex(of: "*") { rest = rest[..<star] }
                return String(rest)
            }
            if !isErase, body.hasPrefix("PMTK001,") {
                let fields = body.dropFirst(8).prefix { $0 != "*" }.split(separator: ",")
                if fields.count >= 3, fields[0] == commandFields.first, fields[1] == commandFields.dropFirst().first,
                   let flag = Int(fields[2]), (0...2).contains(flag) {
                    return nil
                }
            }
        }
        return nil
    }

    /// Model query (`mtk_rd_init`): `$PMTK605` → `$PMTK705,…`. Returns `true` for a Holux GR-245.
    func identify() async throws -> Bool {
        guard let model = try await command("$PMTK605*31\r\n", expect: "PMTK705,", seconds: 10) else {
            throw DeviceProtocolError("This is not an MTK based logger (or it is switched off)")
        }
        guard model.contains("GR-245") else { return false }
        _ = try await command("$PHLX810*35\r\n", expect: "PHLX852,", seconds: 10)
        _ = try await command("$PHLX826*30\r\n", expect: "PHLX859*38", seconds: 10)
        return true
    }

    /// Reads `size` bytes from `address` (`$PMTK182,7,…` → `$PMTK182,8,<address>,<hex>`), retrying three times
    /// after a timeout or a negative acknowledgement. An all-0xFF chunk ends the block early.
    func readBlock(address: Int, size: Int) async throws -> Block {
        let command = MTKDevice.sentence(String(format: "PMTK182,7,%08x,%08x", address, size))
        var retries = 0
        retry: while true {
            await connection.discardInput()  // answers left over from an earlier request that ended early
            try await connection.write(Array(command.utf8))
            var data = [UInt8](repeating: 0, count: size)
            var received = address
            while received < address + size {
                guard let text = try await line() else {
                    retries += 1
                    if retries <= 3 { continue retry }
                    throw DeviceProtocolError("No answer when reading address \(String(format: "%08x", address))")
                }
                reporter.activity()
                if text.hasPrefix("$PMTK182,8,") {
                    let chars = Array(text.utf8)
                    guard chars.count > 20, let dataAddress = Int(String(decoding: chars[11..<19], as: UTF8.self), radix: 16),
                          dataAddress >= address, dataAddress < address + size else { continue }
                    var i = 20
                    var j = dataAddress - address
                    var ff = 0
                    let start = j
                    while i + 3 < chars.count, j < size, let high = Self.hex(chars[i]), let low = Self.hex(chars[i + 1]) {
                        data[j] = high << 4 | low
                        if data[j] == 0xFF { ff += 1 }
                        i += 2
                        j += 1
                    }
                    received = address + j
                    if ff == j - start, j > start {  // 0xFF chunk: end of the data
                        return Block(bytes: dataAddress == address ? [UInt8](repeating: 0xFF, count: j - start)
                                                                   : Array(data[0..<(dataAddress - address)]))
                    }
                } else if text.hasPrefix("$PMTK001,182,7,"), text.dropFirst(15).first != "3" {
                    try await Task.sleep(nanoseconds: 10_000_000)
                    retries += 1
                    if retries <= 3 { continue retry }
                    throw DeviceProtocolError("The logger rejected reading address \(String(format: "%08x", address))")
                }
            }
            return Block(bytes: Array(data[0..<(received - address)]))
        }
    }

    static func hex(_ c: UInt8) -> UInt8? {
        switch c {
        case 0x30...0x39: c - 0x30
        case 0x41...0x46: c - 0x41 + 10
        case 0x61...0x66: c - 0x61 + 10
        default: nil
        }
    }
}
