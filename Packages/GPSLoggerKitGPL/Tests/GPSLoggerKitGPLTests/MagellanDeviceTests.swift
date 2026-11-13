// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import GPSLoggerKit
@testable import GPSLoggerKitGPL

/// A simulated Magellan Meridian/SporTrak (spec `magellan-device`). Each write is one command line.
final class MagellanSimulator: @unchecked Sendable {
    private let lock = NSLock()
    var productID = 33
    var trackPoints = 500
    var waypoints = 20
    var waypointsUnable = false
    var badChecksumBeforeVersion = false
    var silentDuringTrack = false
    private(set) var commands: [String] = []

    func respond(_ written: [UInt8]) -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }
        let line = String(decoding: written, as: UTF8.self)
        let body = String(line.dropFirst().prefix { $0 != "*" })
        commands.append(body)
        var reply = ""
        switch body {
        case "PMGNCMD,VERSION":
            // The rest of an NMEA sentence and a complete one come first (NMEA output is still on).
            reply += "0.0,M,,*47\r\n" + MagellanTestFile.sentence("GPGSA,A,3,01,02,03,,,,,,,,,,2.0,1.0,1.5")
            if badChecksumBeforeVersion { reply += MagellanTestFile.sentence("GPGSA,A,3,01", checksum: 0x00) }
            reply += MagellanTestFile.sentence("PMGNVER,\(productID),3.06,MERIDIAN GPS")
        case "PMGNCMD,TRACK,2":
            for k in 0..<trackPoints {
                reply += MagellanTestFile.track(latitude: 50 + Double(k) * 0.0001, longitude: -8, altitude: k % 300,
                                                time: MagellanTestFile.start.addingTimeInterval(Double(k)))
            }
            if !silentDuringTrack { reply += MagellanTestFile.sentence("PMGNCMD,END") }
        case "PMGNCMD,WAYPOINT":
            if waypointsUnable { return Array(MagellanTestFile.sentence("PMGNCMD,UNABLE").utf8) }
            for k in 0..<waypoints {
                reply += MagellanTestFile.waypoint(latitude: 49 + Double(k) * 0.01, longitude: 7, altitude: k,
                                                   name: "WP\(k)", comment: "Point \(k)")
            }
            reply += MagellanTestFile.sentence("PMGNCMD,END")
        default:
            break
        }
        return Array(reply.utf8)
    }
}

private func device(_ simulator: MagellanSimulator) -> SimulatedDevice {
    SimulatedDevice(baudRate: MagellanDevice.baudRate, initialInput: Array("$GPGGA,120000,50".utf8)) { written, _ in
        simulator.respond(written)
    }
}

/// Collects step messages.
final class StepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    var steps: [String] { lock.withLock { entries } }
    var reporter: DeviceReporter { DeviceReporter(step: { step in self.lock.withLock { self.entries.append(step) } }) }
}

@Suite("Magellan device")
struct MagellanDeviceTests {
    /// Scenario "Prüfsumme eines Befehls".
    @Test func commandChecksum() {
        #expect(MagellanSentences.command("PMGNCMD,VERSION") == Array("$PMGNCMD,VERSION*28\r\n".utf8))
    }

    /// Scenarios "Meridian meldet sich" and "Auslesen".
    @Test func readsTrackAndWaypoints() async throws {
        let simulator = MagellanSimulator()
        let recording = try await MagellanDevice().read(device(simulator), DeviceReporter())
        #expect(recording.tracks.map(\.name) == ["Magellan"])
        #expect(recording.trackPointCount == 500)
        #expect(recording.waypoints.count == 20)
        #expect(recording.waypoints.first?.name == "WP0" && recording.waypoints.first?.comment == "Point 0")
        let first = try #require(recording.tracks.first?.segments.first?.points.first)
        #expect(abs(first.latitude - 50) < 1e-9 && abs(first.longitude + 8) < 1e-9 && first.time == MagellanTestFile.start)
        #expect(simulator.commands == ["PMGNCMD,HANDOFF", "PMGNCMD,VERSION", "PMGNCMD,NMEAOFF", "PMGNCMD,TRACK,2",
                                       "PMGNCMD,WAYPOINT", "PMGNCMD,HANDOFF"])
    }

    /// The GPS 315/320 does not get `NMEAOFF`.
    @Test func gps315GetsNoNMEAOff() async throws {
        let simulator = MagellanSimulator()
        simulator.productID = 24
        _ = try await MagellanDevice().read(device(simulator), DeviceReporter())
        #expect(!simulator.commands.contains("PMGNCMD,NMEAOFF"))
    }

    /// Scenario "Unbekanntes Gerät".
    @Test func unknownProductID() async {
        let simulator = MagellanSimulator()
        simulator.productID = 99
        await #expect(throws: DeviceProtocolError("Unknown receiver type 99, model version '3.06'")) {
            try await MagellanDevice().read(device(simulator), DeviceReporter())
        }
        #expect(simulator.commands.last == "PMGNCMD,HANDOFF")
    }

    /// Scenario "Falsche Baudrate".
    @Test func badChecksumBeforeVersion() async {
        let simulator = MagellanSimulator()
        simulator.badChecksumBeforeVersion = true
        await #expect(throws: DeviceProtocolError("Bad communication. Check the baud rate.")) {
            try await MagellanDevice().read(device(simulator), DeviceReporter())
        }
    }

    /// Scenario "Gerät verstummt": the connection's timeout ends the operation.
    @Test func deviceFallsSilent() async {
        let simulator = MagellanSimulator()
        simulator.silentDuringTrack = true
        await #expect(throws: SimulatedTimeout.self) {
            try await MagellanDevice().read(device(simulator), DeviceReporter())
        }
    }

    /// Scenario "Keine Wegpunkte".
    @Test func noWaypoints() async throws {
        let simulator = MagellanSimulator()
        simulator.waypointsUnable = true
        let log = StepLog()
        let recording = try await MagellanDevice().read(device(simulator), log.reporter)
        #expect(recording.trackPointCount == 500 && recording.waypoints.isEmpty)
        #expect(log.steps.contains("The device sends no waypoints"))
    }
}
