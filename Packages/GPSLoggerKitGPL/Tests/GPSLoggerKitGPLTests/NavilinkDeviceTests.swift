// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import GPSLoggerKit
@testable import GPSLoggerKitGPL

/// A simulated NaviGPS in NAVILINK mode (spec `navilink-device`).
final class NavilinkSimulator: @unchecked Sendable {
    private let lock = NSLock()
    var waypoints: [[UInt8]]
    var trackpoints: [[UInt8]]
    var trackAddress = 0x10000
    var acks = 0
    var corruptChecksum = false

    init(waypoints: Int, trackpoints: Int) {
        self.waypoints = (0..<waypoints).map { Self.waypointRecord($0) }
        self.trackpoints = (0..<trackpoints).map { Self.trackpointRecord($0) }
    }

    static func position(_ lat: Double, _ lon: Double, feet: Int) -> [UInt8] {
        NavilinkLink.le32(Int((lat * 1e7).rounded())) + NavilinkLink.le32(Int((lon * 1e7).rounded())) + NavilinkLink.le16(feet)
    }

    static func time(_ k: Int) -> [UInt8] { [26, 11, 2, 12, UInt8(k / 60 % 60), UInt8(k % 60)] }

    static func waypointRecord(_ k: Int) -> [UInt8] {
        var r = [UInt8](repeating: 0, count: 32)
        r[0] = 0x00; r[1] = 0x40
        r.replaceSubrange(2..<4, with: NavilinkLink.le16(k))
        r.replaceSubrange(4..<10, with: Array(String(format: "WP%04d", k).utf8))
        r.replaceSubrange(12..<22, with: position(50.1 + Double(k) * 0.001, 8.1, feet: 328))
        r.replaceSubrange(22..<28, with: time(k))
        return r
    }

    static func trackpointRecord(_ k: Int) -> [UInt8] {
        var r = [UInt8](repeating: 0, count: 32)
        r.replaceSubrange(0..<2, with: NavilinkLink.le16(k + 1))
        r.replaceSubrange(2..<4, with: NavilinkLink.le16(90))
        r.replaceSubrange(12..<22, with: position(50 + Double(k) * 0.0001, 8, feet: 1000))
        r.replaceSubrange(22..<28, with: time(k))
        r[29] = 18  // 36 km/h
        return r
    }

    func respond(_ written: [UInt8]) -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }
        guard written.count >= 9, written[0] == 0xA0, written[1] == 0xA2 else { return [] }
        let type = written[4]
        let payload = ByteReader(bytes: Array(written[5..<(written.count - 4)]))
        func data(_ bytes: [UInt8]) -> [UInt8] {
            var packet = NavilinkLink.packet(NavilinkDevice.PID.data, bytes)
            if corruptChecksum { packet[packet.count - 4] ^= 0x01 }
            return packet
        }
        switch type {
        case NavilinkDevice.PID.sync: return NavilinkLink.packet(NavilinkDevice.PID.ack)
        case NavilinkDevice.PID.ack: acks += 1; return []
        case NavilinkDevice.PID.queryInformation:
            var info = [UInt8](repeating: 0, count: 32)
            info.replaceSubrange(0..<2, with: NavilinkLink.le16(waypoints.count))
            info.replaceSubrange(4..<8, with: NavilinkLink.le32(trackAddress))
            info.replaceSubrange(12..<14, with: NavilinkLink.le16(trackpoints.count))
            return data(info)
        case NavilinkDevice.PID.queryWaypoints:
            let start = Int(payload.u32le(0)!), count = Int(payload.u16le(4)!)
            return data(Array(waypoints[start..<(start + count)].joined()))
        case NavilinkDevice.PID.readTrackpoints:
            let start = (Int(payload.u32le(0)!) - trackAddress) / 32, count = Int(payload.u16le(4)!) / 32
            return data(Array(trackpoints[start..<(start + count)].joined()))
        default:
            return NavilinkLink.packet(NavilinkDevice.PID.nak)
        }
    }
}

private func connection(_ simulator: NavilinkSimulator) -> SimulatedDevice {
    SimulatedDevice(baudRate: NavilinkDevice.baudRate) { written, _ in simulator.respond(written) }
}

@Suite("Navilink device")
struct NavilinkDeviceTests {
    /// Scenario "Auslesen": 40 waypoints (two requests) and 600 track points (two requests, each acknowledged).
    @Test func readsWaypointsAndTrack() async throws {
        let simulator = NavilinkSimulator(waypoints: 40, trackpoints: 600)
        let recording = try await NavilinkDevice().read(connection(simulator), DeviceReporter())
        #expect(recording.waypoints.count == 40)
        #expect(recording.waypoints.first?.name == "WP0000")
        #expect(abs((recording.waypoints.first?.elevation ?? 0) - 99.97) < 0.01)
        #expect(recording.trackPointCount == 600)
        let p = try #require(recording.tracks.first?.segments.first?.points.first)
        #expect(p.latitude == 50 && p.longitude == 8 && abs((p.elevation ?? 0) - 304.8) < 0.001)
        #expect(p.time == ISO8601DateFormatter().date(from: "2026-11-02T12:00:00Z"))
        #expect(p.quality.course == 90 && p.quality.speed == 10)
        #expect(simulator.acks == 2)
        #expect(NavilinkDevice().eraseSupport == .unsupported)
    }

    @Test func packetFormat() {
        #expect(NavilinkLink.packet(0xD6) == [0xA0, 0xA2, 0x01, 0x00, 0xD6, 0xD6, 0x00, 0xB0, 0xB3])
    }

    /// Scenario "Nicht im NAVILINK-Modus".
    @Test func notInNavilinkMode() async {
        let nmea = SimulatedDevice { _, _ in Array("$GPRMC,120000,A*00\r\n".utf8) }
        await #expect(throws: DeviceProtocolError("Bad packet header. Is the device in NAVILINK mode?")) {
            try await NavilinkDevice().read(nmea, DeviceReporter())
        }
    }

    /// Scenario "Prüfsummenfehler".
    @Test func checksumError() async {
        let simulator = NavilinkSimulator(waypoints: 1, trackpoints: 1)
        simulator.corruptChecksum = true
        await #expect(throws: DeviceProtocolError("Checksum error")) {
            try await NavilinkDevice().read(connection(simulator), DeviceReporter())
        }
    }
}
