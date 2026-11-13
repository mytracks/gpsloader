// Test helper: a simulated logger behind a DeviceConnection (design D1 of change device-mode).
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GPSLoggerKit
@testable import GPSLoggerKitGPL

struct SimulatedTimeout: Error, Equatable {}

/// A device that reacts to written bytes. `respond` gets every write and the current baud rate and
/// returns the bytes the device sends back (appended to the input buffer). Reads that cannot be
/// satisfied from the buffer fail immediately with `SimulatedTimeout`.
actor SimulatedDevice: DeviceConnection {
    typealias Responder = @Sendable (_ written: [UInt8], _ baudRate: Int) -> [UInt8]

    private var input: [UInt8]
    private let respond: Responder
    private(set) var written: [[UInt8]] = []
    private(set) var baudRate: Int
    private(set) var baudChanges: [Int] = []

    init(baudRate: Int = 9600, initialInput: [UInt8] = [], respond: @escaping Responder) {
        self.baudRate = baudRate
        input = initialInput
        self.respond = respond
    }

    func write(_ bytes: [UInt8]) async throws {
        try Task.checkCancellation()
        written.append(bytes)
        input += respond(bytes, baudRate)
    }

    func read(count: Int, timeout: TimeInterval) async throws -> [UInt8] {
        try Task.checkCancellation()
        guard input.count >= count else { throw SimulatedTimeout() }
        let bytes = Array(input.prefix(count))
        input.removeFirst(count)
        return bytes
    }

    func readUntil(_ terminator: [UInt8], maxLength: Int, timeout: TimeInterval) async throws -> [UInt8] {
        try Task.checkCancellation()
        guard !terminator.isEmpty, input.count >= terminator.count else { throw SimulatedTimeout() }
        for end in terminator.count...input.count where Array(input[(end - terminator.count)..<end]) == terminator {
            let bytes = Array(input.prefix(end - terminator.count))
            input.removeFirst(end)
            return bytes
        }
        throw SimulatedTimeout()
    }

    func discardInput() async {
        input.removeAll()
    }

    func setBaudRate(_ rate: Int) async throws {
        baudRate = rate
        baudChanges.append(rate)
    }

    /// Bytes the device sends without being asked (e.g. NMEA output).
    func inject(_ bytes: [UInt8]) {
        input += bytes
    }

    var pendingInput: [UInt8] { input }
}
