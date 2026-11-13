// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import GPSLoggerKit
@testable import GPSLoggerKitGPL

/// A simulated SkyTraq Venus logger (spec `skytraq-device`), answering frames as described in skytraq.cc.
final class SkyTraqSimulator: @unchecked Sendable {
    private let lock = NSLock()
    var deviceBaud: Int
    var memory: [UInt8]  // sectors of 4096 bytes
    var totalSectors: Int
    var usedSectors: Int
    var multiReadSupported = true
    var erased = false
    var restarted = false
    var commands: [UInt8] = []

    init(baud: Int, memory: [UInt8], usedSectors: Int, totalSectors: Int = 250) {
        deviceBaud = baud
        self.memory = memory
        self.usedSectors = usedSectors
        self.totalSectors = totalSectors
    }

    static func ack(_ id: UInt8) -> [UInt8] { SkyTraqLink.frame([0x83, id]) }
    static func nack(_ id: UInt8) -> [UInt8] { SkyTraqLink.frame([0x84, id]) }

    func sector(_ index: Int) -> [UInt8] {
        let start = index * 4096
        guard start < memory.count else { return [UInt8](repeating: 0xFF, count: 4096) }
        return Array(memory[start..<min(start + 4096, memory.count)]) + [UInt8](repeating: 0xFF, count: max(0, start + 4096 - memory.count))
    }

    func respond(_ written: [UInt8], baud: Int) -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }
        guard baud == deviceBaud, written.count >= 7, written[0] == 0xA0, written[1] == 0xA1 else { return [] }
        let payload = Array(written[4..<(written.count - 3)])
        commands.append(payload[0])
        switch payload[0] {
        case 0x02:  // query software version
            return Self.ack(0x02) + SkyTraqLink.frame([0x80, 0x01] + [UInt8](repeating: 1, count: 12))
        case 0x05:  // configure serial port
            let rates = [4800, 9600, 19200, 38400, 57600, 115_200, 230_400]
            let reply = Self.ack(0x05)
            deviceBaud = rates[Int(payload[2])]
            return reply
        case 0x17:  // log status
            var status = [UInt8](repeating: 0, count: 35)
            status[0] = 0x94
            let free = totalSectors - usedSectors
            status[5] = UInt8(free & 0xFF); status[6] = UInt8(free >> 8)
            status[7] = UInt8(totalSectors & 0xFF); status[8] = UInt8(totalSectors >> 8)
            return Self.ack(0x17) + SkyTraqLink.frame(status)
        case 0x1D:  // read multiple sectors
            guard multiReadSupported else { return Self.nack(0x1D) }
            let first = Int(payload[1]) << 8 | Int(payload[2]), count = Int(payload[3]) << 8 | Int(payload[4])
            let data = (first..<(first + count)).flatMap { sector($0) }
            return Self.ack(0x1D) + data + SkyTraqDevice.sectorReadEnd + [SkyTraqLink.checksum(data), 0x0D, 0x0A, 0, 0, 0]
        case 0x1B:  // read single sector: data without trailing 0xFF
            var data = sector(Int(payload[1]))
            while data.last == 0xFF { data.removeLast() }
            return Self.ack(0x1B) + data + SkyTraqDevice.sectorReadEnd + [SkyTraqLink.checksum(data)]
        case 0x19:
            erased = true
            return Self.ack(0x19)
        case 0x01:
            restarted = true
            return Self.ack(0x01)
        default:
            return Self.nack(payload[0])
        }
    }
}

private func device(for simulator: SkyTraqSimulator) -> SimulatedDevice {
    SimulatedDevice(baudRate: 9600) { written, baud in simulator.respond(written, baud: baud) }
}

private func driver(initial: Int? = nil, download: Int = 230_400) -> SkyTraqDevice {
    var driver = SkyTraqDevice(initialBaudRate: initial, downloadBaudRate: download)
    driver.reference = { skyTraqReference }
    return driver
}

@Suite("SkyTraq device")
struct SkyTraqDeviceTests {
    /// Scenario "Auslesen": probing at 38400, download at 230400, restart, same points as the dump decoder.
    @Test func readsTheMemory() async throws {
        let dump = SkyTraqTestDump.venus()
        let simulator = SkyTraqSimulator(baud: 38400, memory: dump.bytes, usedSectors: 1)
        let connection = device(for: simulator)
        let progress = ProgressLog()
        let recording = try await driver().read(connection, DeviceReporter(progress: { done, _, _ in progress.add(done) }))
        // The status reports one used sector, so sectors 0 and 1 are read (used + 1, as in the source).
        #expect(recording.trackPointCount == 516)
        #expect(recording.waypoints.count == 2)
        let baudChanges = await connection.baudChanges
        #expect(Array(baudChanges.suffix(2)) == [230_400, 38400])  // switched for the download and back
        #expect(baudChanges.contains(38400))
        #expect(simulator.restarted)
        #expect(simulator.commands.contains(0x1D))
        #expect(!progress.values.isEmpty)
    }

    /// Scenario "Bekannte Baudrate": only the given rate is probed.
    @Test func initialBaudRate() async throws {
        let simulator = SkyTraqSimulator(baud: 38400, memory: SkyTraqTestDump.venus().bytes, usedSectors: 2)
        let connection = device(for: simulator)
        _ = try await driver(initial: 38400, download: 38400).read(connection, DeviceReporter())
        #expect(await connection.baudChanges == [38400])
    }

    /// Scenario "Einzelne Sektoren": NACK on the multi-sector read falls back to single sectors.
    @Test func singleSectorFallback() async throws {
        let simulator = SkyTraqSimulator(baud: 9600, memory: SkyTraqTestDump.venus().bytes, usedSectors: 2)
        simulator.multiReadSupported = false
        let recording = try await driver(download: 9600).read(device(for: simulator), DeviceReporter())
        #expect(recording.trackPointCount == 517)
        #expect(simulator.commands.filter { $0 == 0x1B }.count == 3)  // used + 1, as in the source
    }

    /// Scenario "Kein Logger".
    @Test func noLogger() async {
        let silent = SimulatedDevice { _, _ in [] }
        await #expect(throws: DeviceProtocolError("No SkyTraq logger found on this port")) {
            try await driver().read(silent, DeviceReporter())
        }
    }

    /// Scenario "Speicher löschen".
    @Test func erase() async throws {
        let simulator = SkyTraqSimulator(baud: 115_200, memory: [], usedSectors: 0)
        try await driver().erase(device(for: simulator), DeviceReporter())
        #expect(simulator.erased && simulator.restarted)
        #expect(driver().eraseSupport == .supported)
    }

    /// Scenario "Prüfsummenfehler".
    @Test func checksumError() async {
        let corrupt = SimulatedDevice { written, _ in
            guard written.count > 4, written[4] == 0x02 else { return [] }
            var ack = SkyTraqSimulator.ack(0x02)
            ack[ack.count - 3] ^= 0xFF
            return ack
        }
        await #expect(throws: DeviceProtocolError.self) {
            try await driver().read(corrupt, DeviceReporter())
        }
    }

    /// Writes the GPX of a download from the simulator for the comparison with gpsbabel (task 3.2).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GPSLOGGERKITGPL_COMPARE_DIR"] != nil))
    func writeComparisonGPX() async throws {
        let directory = try #require(ProcessInfo.processInfo.environment["GPSLOGGERKITGPL_COMPARE_DIR"])
        let simulator = SkyTraqSimulator(baud: 9600, memory: SkyTraqTestDump.venus().bytes, usedSectors: 2)
        let recording = try await driver(download: 9600).read(device(for: simulator), DeviceReporter())
        try GPXWriter(creator: "compare").data(for: recording, createdAt: Date())
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent("skytraq-device.gpx"))
    }

    @Test func frameAndUsedLength() {
        #expect(SkyTraqLink.frame([0x02, 0x01]) == [0xA0, 0xA1, 0x00, 0x02, 0x02, 0x01, 0x03, 0x0D, 0x0A])
        #expect(SkyTraqDump.usedLength(ofSector: [UInt8](repeating: 0xFF, count: 4096)) == 0)
        #expect(SkyTraqDump.usedLength(ofSector: Array(SkyTraqTestDump.venus().bytes.prefix(4096))) == 4082)
    }
}
