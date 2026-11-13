// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import GPSLoggerKit
@testable import GPSLoggerKitGPL

/// A trivial protocol: sends "GET\r\n", the device answers "lat,lon\r\n" lines and "END\r\n".
private struct LineProtocol: DeviceProtocol {
    func read(_ connection: any DeviceConnection, _ reporter: DeviceReporter) async throws -> Recording {
        try await connection.write(Array("GET\r\n".utf8))
        var points: [TrackPoint] = []
        while true {
            let line = String(decoding: try await connection.readUntil([0x0D, 0x0A], maxLength: 64, timeout: 1), as: UTF8.self)
            if line == "END" { break }
            let parts = line.split(separator: ",").compactMap { Double($0) }
            guard parts.count == 2 else { throw DeviceProtocolError("Unexpected answer: \(line)") }
            points.append(TrackPoint(latitude: parts[0], longitude: parts[1]))
            reporter.progress(points.count, of: 2)
        }
        return Recording(tracks: [Track(segments: [TrackSegment(points: points)])])
    }
}

@Suite("Device protocols")
struct DeviceProtocolTests {
    /// Spec `logger-kit-gpl`, "Simuliertes Gerät".
    @Test func simulatedDevice() async throws {
        let device = SimulatedDevice { written, _ in
            written == Array("GET\r\n".utf8) ? Array("50.0,8.0\r\n50.1,8.1\r\nEND\r\n".utf8) : []
        }
        let reports = ProgressLog()
        let recording = try await LineProtocol().read(device, DeviceReporter(progress: { done, _, _ in reports.add(done) }))
        #expect(recording.trackPointCount == 2)
        #expect(reports.values == [1, 2])
        #expect(LineProtocol().eraseSupport == .unsupported)
    }

    /// Spec `logger-kit-gpl`, "Gemeinsame Schnittstelle": the drivers of this package fulfil the contract of GPSLoggerKit.
    @Test func driversUseTheContractOfGPSLoggerKit() {
        let drivers: [any GPSLoggerKit.DeviceProtocol] = [NavilinkDevice(), MagellanDevice(), ITrackUDevice(), IGotUDevice(variant: .serial)]
        #expect(drivers.map(\.eraseSupport) == [.unsupported, .unsupported, .unsupported, .experimental])
    }

    @Test func timeoutReachesTheCaller() async {
        let device = SimulatedDevice { _, _ in Array("50.0,8.0\r\n".utf8) }
        await #expect(throws: SimulatedTimeout.self) {
            try await LineProtocol().read(device, DeviceReporter())
        }
    }

    @Test func protocolErrorAndDefaultErase() async {
        let device = SimulatedDevice { _, _ in Array("garbage\r\n".utf8) }
        await #expect(throws: DeviceProtocolError("Unexpected answer: garbage")) {
            try await LineProtocol().read(device, DeviceReporter())
        }
        await #expect(throws: DeviceProtocolError.self) {
            try await LineProtocol().erase(device, DeviceReporter())
        }
    }
}

/// Thread-safe collector for reports in tests.
final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int] = []

    func add(_ value: Int) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
