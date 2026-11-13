// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import GPSLoggerKit
@testable import GPSLoggerKitGPL

/// A 16-byte iTrackU record (little endian), see spec `itracku-device`.
func itrackuRecord(latitude: Double, longitude: Double, altitude: Int, knots: Int, time: Date) -> [UInt8] {
    func encode(_ degrees: Double) -> UInt32 {
        let value = abs(degrees)
        let d = floor(value)
        return UInt32(d) * 1_000_000 + UInt32(((value - d) * 600_000).rounded()) + (degrees < 0 ? 0x8000_0000 : 0)
    }
    let c = Calendar.utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: time)
    let t = UInt32(c.second!) | UInt32(c.minute!) << 6 | UInt32(c.hour!) << 12 | UInt32(c.day!) << 17
        | UInt32(c.month!) << 22 | UInt32(c.year! - 2000) << 26
    func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8(v >> (8 * $0) & 0xFF) } }
    return le32(encode(longitude)) + le32(encode(latitude)) + le32(t)
        + [UInt8(altitude & 0xFF), UInt8(altitude >> 8 & 0xFF), UInt8(knots), 0xFF]
}

/// A simulated iTrackU behind a `SimulatedDevice`.
final class ITrackUSimulator: @unchecked Sendable {
    private let lock = NSLock()
    var answersDetection = true
    var records: [[UInt8]]
    var sendsEndMarker = true
    private(set) var writes: [[UInt8]] = []

    init(records: [[UInt8]]) {
        self.records = records
    }

    static let start = Date(timeIntervalSince1970: 1_793_620_800)  // 2026-11-02T12:00:00Z

    static func track(_ count: Int) -> [[UInt8]] {
        (0..<count).map { k in
            itrackuRecord(latitude: 50 + Double(k) * 0.0001, longitude: -8 - Double(k) * 0.0001, altitude: 100 + k % 50,
                          knots: k % 20, time: start.addingTimeInterval(Double(k)))
        }
    }

    func respond(_ written: [UInt8]) -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }
        writes.append(written)
        switch written {
        case ITrackUDevice.string("WP AP-Exit"):
            return Array("$GPRMC,stale\r\n".utf8)  // discarded by the driver
        case ITrackUDevice.string("W'P Camera Detect"):
            return answersDetection ? Array("$GPGGA,1*00\r\nWP GPS+BT".utf8) + [0] : Array("$GPGGA,1*00\r\n".utf8)
        case ITrackUDevice.readCommand:
            return records.flatMap { $0 } + (sendsEndMarker ? Array("WP Update Over".utf8) + [0] : [])
        default:
            return []
        }
    }
}

private func device(_ simulator: ITrackUSimulator) -> SimulatedDevice {
    SimulatedDevice(baudRate: ITrackUDevice.baudRate) { written, _ in simulator.respond(written) }
}

@Suite("iTrackU device")
struct ITrackUDeviceTests {
    /// Scenarios "Gerät antwortet" and "Speicher mit Endemarke" (all records arrive with the marker).
    @Test func readsTheMemory() async throws {
        let simulator = ITrackUSimulator(records: ITrackUSimulator.track(300))
        let recording = try await ITrackUDevice().read(device(simulator), DeviceReporter())
        #expect(recording.tracks.map(\.name) == ["iTrackU"])
        #expect(recording.trackPointCount == 300)
        let last = try #require(recording.tracks.first?.segments.first?.points.last)
        #expect(last.time == ITrackUSimulator.start.addingTimeInterval(299))
        #expect(simulator.writes == [ITrackUDevice.string("WP AP-Exit"), ITrackUDevice.string("W'P Camera Detect"),
                                     ITrackUDevice.readCommand])
    }

    /// Scenario "Anderes Gerät".
    @Test func otherDevice() async {
        let simulator = ITrackUSimulator(records: [])
        simulator.answersDetection = false
        await #expect(throws: DeviceProtocolError("No iTrackU found on this port")) {
            try await ITrackUDevice().read(device(simulator), DeviceReporter())
        }
    }

    /// Scenario "Gerät verstummt".
    @Test func deviceFallsSilent() async {
        let simulator = ITrackUSimulator(records: ITrackUSimulator.track(100))
        simulator.sendsEndMarker = false
        await #expect(throws: SimulatedTimeout.self) {
            try await ITrackUDevice().read(device(simulator), DeviceReporter())
        }
    }

    /// Scenario "Umrechnung".
    @Test func conversion() throws {
        let time = try #require(ISO8601DateFormatter().date(from: "2026-11-02T12:34:56Z"))
        var record = itrackuRecord(latitude: 50.5, longitude: -8.25, altitude: 123, knots: 10, time: time)
        #expect(Array(record[4..<8]) == [0x60, 0x84, 0xFF, 0x02])  // 50300000
        #expect(Array(record[0..<4]) == [0xF0, 0x5B, 0x7C, 0x80])  // 0x80000000 + 8150000
        let point = try #require(ITrackUDevice.decode(record).first)
        #expect(abs(point.latitude - 50.5) < 1e-9 && abs(point.longitude + 8.25) < 1e-9)
        #expect(point.elevation == 123 && point.time == time)
        #expect(abs((point.quality.speed ?? 0) - 5.144) < 0.001)
        record[13] = 0xFF  // altitude is read unsigned, like the source
        #expect(ITrackUDevice.decode(record).first?.elevation == Double(0xFF7B))
    }

    /// Scenario "Leerer Speicherplatz".
    @Test func emptySlot() {
        let data = [UInt8](repeating: 0xFF, count: 16) + ITrackUSimulator.track(1)[0] + [0x01, 0x02]
        #expect(ITrackUDevice.decode(data).count == 1)
    }
}
