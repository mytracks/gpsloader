import Foundation

/// Byte oriented, bidirectional connection to a device (spec `serial-transport`).
///
/// Drivers talk to devices only through this abstraction, so the same driver can run
/// against a real serial port, a scripted mock or a recorded diagnostic capture.
///
/// Timeouts are *inactivity* timeouts: a read fails with `LoggerError(.timeout)` when no
/// byte arrives for `timeout` seconds before the read is complete. Every arriving byte
/// restarts the timer, so large reads at low baud rates do not need huge timeouts.
///
/// All operations throw `LoggerError(.cancelled)` when the calling task is cancelled.
public protocol ByteTransport: Sendable {
    /// Human readable identifier of the endpoint, e.g. the port path.
    var identifier: String { get }

    /// Opens the connection.
    func open() async throws

    /// Sends all bytes.
    func write(_ bytes: [UInt8]) async throws

    /// Reads exactly `count` bytes.
    func read(count: Int, timeout: TimeInterval) async throws -> [UInt8]

    /// Reads until `terminator` has been received and returns the bytes *without* the terminator.
    /// Fails with `.protocolError` when `maxLength` bytes arrive without a terminator.
    func readUntil(_ terminator: [UInt8], maxLength: Int, timeout: TimeInterval) async throws -> [UInt8]

    /// Closes the connection. Safe to call more than once.
    func close() async
}
