// Connection and driver contract for logger protocols (change device-mode). Own code.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GPSLoggerKit

/// Byte oriented connection to a logger, provided by the app (serial port, USB HID, simulation).
///
/// Timeouts are inactivity timeouts. Timeout, disconnection and cancellation are reported as the
/// connection's own errors; protocols pass them on unchanged.
public protocol DeviceConnection: Sendable {
    func write(_ bytes: [UInt8]) async throws
    /// Reads exactly `count` bytes.
    func read(count: Int, timeout: TimeInterval) async throws -> [UInt8]
    /// Reads until `terminator` and returns the bytes without it.
    func readUntil(_ terminator: [UInt8], maxLength: Int, timeout: TimeInterval) async throws -> [UInt8]
    /// Drops bytes that have arrived but were not read yet.
    func discardInput() async
    /// Switches the baud rate of a serial connection; other connections ignore it.
    func setBaudRate(_ rate: Int) async throws
}

/// Progress and activity reports of a protocol.
public struct DeviceReporter: Sendable {
    let onProgress: @Sendable (_ completed: Int, _ total: Int, _ step: String?) -> Void
    let onStep: @Sendable (String) -> Void
    let onActivity: @Sendable () -> Void

    public init(progress: @escaping @Sendable (_ completed: Int, _ total: Int, _ step: String?) -> Void = { _, _, _ in },
                step: @escaping @Sendable (String) -> Void = { _ in },
                activity: @escaping @Sendable () -> Void = {}) {
        onProgress = progress
        onStep = step
        onActivity = activity
    }

    public func progress(_ completed: Int, of total: Int, step: String? = nil) { onProgress(completed, total, step) }
    public func step(_ text: String) { onStep(text) }
    public func activity() { onActivity() }
}

/// The device answered something the protocol did not expect, or the device is not supported.
public struct DeviceProtocolError: Error, Sendable, Equatable, CustomStringConvertible {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// Whether a protocol can erase the logger memory.
public enum DeviceErase: Sendable, Equatable {
    case unsupported
    case supported
    /// Supported but not verified with hardware; the user must be warned.
    case experimental
}

/// A logger protocol: reads the recording and optionally erases the memory.
public protocol DeviceProtocol: Sendable {
    var eraseSupport: DeviceErase { get }
    func read(_ connection: any DeviceConnection, _ reporter: DeviceReporter) async throws -> Recording
    func erase(_ connection: any DeviceConnection, _ reporter: DeviceReporter) async throws
}

extension DeviceProtocol {
    public var eraseSupport: DeviceErase { .unsupported }

    public func erase(_ connection: any DeviceConnection, _ reporter: DeviceReporter) async throws {
        throw DeviceProtocolError("Erasing is not supported.")
    }
}

/// Helpers shared by the protocols.
extension DeviceConnection {
    /// Reads until `terminator`, as text (Latin-1 safe), without the terminator.
    func readLine(terminator: [UInt8] = [0x0D, 0x0A], maxLength: Int = 4096, timeout: TimeInterval) async throws -> String {
        let bytes = try await readUntil(terminator, maxLength: maxLength, timeout: timeout)
        return String(decoding: bytes, as: UTF8.self)
    }
}
