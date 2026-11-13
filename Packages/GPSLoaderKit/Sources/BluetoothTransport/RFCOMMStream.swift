import Foundation
import LoggerCore

/// Bytes received on a Bluetooth RFCOMM channel, filled on the main run loop and read by the transport
/// (spec `bluetooth-transport`, "Daten übertragen").
final class RFCOMMInputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: [UInt8] = []
    private var closedReason: String?

    func append(_ data: UnsafeRawBufferPointer) {
        lock.lock()
        bytes += data
        lock.unlock()
    }

    func append(_ data: [UInt8]) {
        data.withUnsafeBytes(append)
    }

    /// Marks the channel as closed; readers waiting for more data fail.
    func close(reason: String) {
        lock.lock()
        if closedReason == nil { closedReason = reason }
        lock.unlock()
    }

    /// `count` bytes, or `nil` when fewer are available.
    func take(_ count: Int) -> [UInt8]? {
        lock.lock()
        defer { lock.unlock() }
        guard bytes.count >= count else { return nil }
        defer { bytes.removeFirst(count) }
        return Array(bytes.prefix(count))
    }

    /// The bytes before `terminator` (removing both), or `nil` when it has not arrived.
    func take(until terminator: [UInt8]) -> [UInt8]? {
        lock.lock()
        defer { lock.unlock() }
        guard !terminator.isEmpty, bytes.count >= terminator.count else { return nil }
        for end in terminator.count...bytes.count where Array(bytes[(end - terminator.count)..<end]) == terminator {
            defer { bytes.removeFirst(end) }
            return Array(bytes.prefix(end - terminator.count))
        }
        return nil
    }

    var available: Int {
        lock.lock()
        defer { lock.unlock() }
        return bytes.count
    }

    var closed: String? {
        lock.lock()
        defer { lock.unlock() }
        return closedReason
    }
}

/// Reading from an `RFCOMMInputBuffer` with an inactivity timeout: every arriving byte restarts the timer.
struct RFCOMMStream: Sendable {
    let buffer: RFCOMMInputBuffer
    let identifier: String
    /// Polling interval while waiting for data.
    var interval: UInt64 = 5_000_000

    func read(count: Int, timeout: TimeInterval) async throws -> [UInt8] {
        try await wait(timeout: timeout) { buffer.take(count) }
    }

    func readUntil(_ terminator: [UInt8], maxLength: Int, timeout: TimeInterval) async throws -> [UInt8] {
        try await wait(timeout: timeout) {
            if let line = buffer.take(until: terminator) { return line }
            if buffer.available >= maxLength + terminator.count {
                let head = buffer.take(maxLength) ?? []
                throw LoggerError(.protocolError, detail: "\(identifier): no terminator within \(maxLength) bytes: \(head.printableASCII)")
            }
            return nil
        }
    }

    private func wait(timeout: TimeInterval, _ attempt: () throws -> [UInt8]?) async throws -> [UInt8] {
        var deadline = Date().addingTimeInterval(timeout)
        var available = buffer.available
        while true {
            if let bytes = try attempt() { return bytes }
            if let reason = buffer.closed { throw LoggerError(.deviceNotFound, detail: "\(identifier): \(reason)") }
            if Task.isCancelled { throw LoggerError(.cancelled) }
            let now = buffer.available
            if now != available {
                available = now
                deadline = Date().addingTimeInterval(timeout)
            }
            if Date() > deadline { throw LoggerError(.timeout, detail: "\(identifier): no answer") }
            try? await Task.sleep(nanoseconds: interval)
        }
    }
}
