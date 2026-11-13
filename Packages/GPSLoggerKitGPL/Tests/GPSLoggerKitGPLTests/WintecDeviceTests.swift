// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import GPSLoggerKit
@testable import GPSLoggerKitGPL

/// A simulated Wintec logger (spec `wintec-device`) answering like described in wbt-200.cc.
final class WintecSimulator: @unchecked Sendable {
    private let lock = NSLock()
    let type: WintecDevice.DeviceType
    /// WBT-200: raw records; WBT-201/WSG-1000: the log area.
    var memory: [UInt8]
    var recordCount = 0
    var logStart = 0, logEnd = 0, areaStart = 0, areaEnd = 0
    var corruptFirstChunk = false
    var erased = false
    var commands: [String] = []

    init(type: WintecDevice.DeviceType, memory: [UInt8]) {
        self.type = type
        self.memory = memory
    }

    func respond(_ written: [UInt8], baud: Int) -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }
        let command = String(decoding: written, as: UTF8.self).trimmingCharacters(in: .newlines)
        let expectedBaud = type == .wbt200 ? WintecDevice.wbt200Baud : WintecDevice.wbt201Baud
        guard baud == expectedBaud else { return [] }
        commands.append(command)
        let nmea = "$GPRMC,120000,A,5000.000,N,00800.000,E,0.0,0.0,021126,,*15\r\n"
        func line(_ text: String) -> [UInt8] { Array((nmea + text + "\r\n").utf8) }
        switch type {
        case .wbt200:
            switch command {
            case "$PFST,NORMAL", "$PFST,FIRMWAREVERSION": return line(command + ",1.0")
            case "$PFST,READLOGGER":
                let count = recordCount - 1
                return line(command) + [0, 0, UInt8(count & 0xFF), UInt8(count >> 8 & 0xFF), 0, 0] + memory
            default:
                if command.hasPrefix("$PFST,REMOVEFILE") || command.hasPrefix("$PFST,FFSRECLAIM") {
                    erased = true
                    return line(command)
                }
                return []
            }
        case .wbt201, .wsg1000:
            if command == "@AL" { return type == .wbt201 ? line("@AL") : [] }
            if command == "@AL,2,3" { return line("@AL,2,3,OK") }
            let values = ["@AL,7,1": "WBT201", "@AL,8,1": "1.0", "@AL,8,2": "1.0", "@AL,8,3": "1.0",
                          "@AL,5,1": "\(logStart)", "@AL,5,2": "\(logEnd)", "@AL,5,9": "\(areaStart)",
                          "@AL,5,10": "\(areaEnd)"]
            if let value = values[command] { return line(command + "," + value) }
            if command == "@AL,5,6" { erased = true; return line(command) }
            if command == "@AL,2,1" { return line(command) }
            if command.hasPrefix("@AL,5,3,"), let position = Int(command.dropFirst(8)) {
                let limit = position < logEnd || logStart < logEnd ? logEnd : areaEnd
                let want = min(4096, limit - position)
                let data = Array(memory[position..<(position + want)])
                var checksum = data.reduce(UInt8(0), ^)
                if corruptFirstChunk { corruptFirstChunk = false; checksum ^= 0xFF }
                var reply = data + Array(String(format: "@AL,CS,%02X,0\r\n", checksum).utf8)
                if type == .wbt201 { reply += Array((command + "\r\n").utf8) }
                return reply
            }
            return []
        }
    }
}

private func connection(_ simulator: WintecSimulator) -> SimulatedDevice {
    SimulatedDevice(baudRate: 9600) { written, baud in simulator.respond(written, baud: baud) }
}

/// WBT-201 records (16 bytes) as in TK1 files.
private func wbt201Records(_ count: Int, startFlags: Set<Int> = [0], waypoints: Set<Int> = []) -> [UInt8] {
    (0..<count).flatMap { k in
        let flags: UInt16 = (startFlags.contains(k) ? 0x01 : 0) | (waypoints.contains(k) ? 0x02 : 0)
        return WintecTestFile.record16(flags: flags, time: WintecTestFile.stamp(2026, 11, 2, 12, k / 60, k % 60),
                                       latitude: 50 + Double(k) * 0.0001, longitude: 8, altitude: Int16(k))
    }
}

@Suite("Wintec device")
struct WintecDeviceTests {
    /// Scenario "WBT-200".
    @Test func wbt200() async throws {
        let simulator = WintecSimulator(type: .wbt200, memory: WintecTestFile.binFixture())
        simulator.recordCount = 5
        let recording = try await WintecDevice().read(connection(simulator), DeviceReporter())
        #expect(recording.tracks.map(\.pointCount) == [2, 3])
        #expect(recording.tracks.first?.segments.first?.points.first?.elevation == 123.4)
        #expect(simulator.commands.contains("$PFST,READLOGGER"))
    }

    /// Scenario "WBT-201 mit Prüfsumme": 300 records = two chunks, the first one is sent with a wrong
    /// checksum and requested again.
    @Test func wbt201() async throws {
        let memory = wbt201Records(300, startFlags: [0, 200], waypoints: [5])
        let simulator = WintecSimulator(type: .wbt201, memory: memory)
        (simulator.logStart, simulator.logEnd, simulator.areaStart, simulator.areaEnd) = (0, memory.count, 0, 8192)
        simulator.corruptFirstChunk = true
        let recording = try await WintecDevice().read(connection(simulator), DeviceReporter())
        #expect(recording.tracks.map(\.pointCount) == [200, 100])
        #expect(recording.waypoints.count == 1)
        #expect(simulator.commands.filter { $0 == "@AL,5,3,0" }.count == 2)
        #expect(simulator.commands.last == "@AL,2,1")
    }

    /// Scenario "Überschriebener Ringpuffer": the log wrapped around; reading starts at the oldest data.
    @Test func wrappedRingBuffer() async throws {
        let older = wbt201Records(100)  // written first, at the end of the area
        let newer = Array(wbt201Records(150).suffix(50 * 16))  // continues at the start of the area
        var memory = [UInt8](repeating: 0, count: 4096)
        memory.replaceSubrange(0..<newer.count, with: newer)
        memory.replaceSubrange((4096 - older.count)..<4096, with: older)
        let simulator = WintecSimulator(type: .wsg1000, memory: memory)
        (simulator.logStart, simulator.logEnd, simulator.areaStart, simulator.areaEnd) = (4096 - older.count, newer.count, 0, 4096)
        let recording = try await WintecDevice().read(connection(simulator), DeviceReporter())
        let points = recording.tracks.flatMap { $0.segments.flatMap(\.points) }
        #expect(points.count == 150)
        #expect(points.first?.elevation == 0 && points.last?.elevation == 149)
    }

    /// Scenario "Kein Wintec-Gerät".
    @Test func unknownDevice() async {
        await #expect(throws: DeviceProtocolError("Can't determine the Wintec device type")) {
            try await WintecDevice().read(SimulatedDevice { _, _ in [] }, DeviceReporter())
        }
    }

    /// Scenario "Speicher löschen" for both protocol variants.
    @Test(arguments: [WintecDevice.DeviceType.wbt200, .wbt201])
    func erase(type: WintecDevice.DeviceType) async throws {
        let simulator = WintecSimulator(type: type, memory: [])
        try await WintecDevice().erase(connection(simulator), DeviceReporter())
        #expect(simulator.erased)
    }
}
