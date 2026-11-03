import Foundation
import LoggerCore

/// Raised by `MockTransport` when a driver deviates from the script.
public struct MockTransportMismatch: Error, Sendable, CustomStringConvertible {
    public var stepIndex: Int
    public var expected: [UInt8]?
    public var actual: [UInt8]

    public var description: String {
        let expectedText = expected.map { "\($0.hexString) (\($0.printableASCII))" } ?? "<no further write expected>"
        return "Unexpected write at step \(stepIndex): expected \(expectedText), got \(actual.hexString) (\(actual.printableASCII))"
    }
}

/// A scripted `ByteTransport` for tests: the script lists the bytes a driver is expected to
/// write and what the simulated device answers.
public actor MockTransport: ByteTransport {
    /// One step of the device dialog.
    public enum Step: Sendable {
        /// The driver must write exactly these bytes next.
        case expect([UInt8])
        /// The device sends these bytes (after an optional delay). Steps of this kind that follow an
        /// `expect` are triggered by the matching write; steps at the start are sent on `open()`.
        case reply([UInt8], delay: TimeInterval = 0)

        public static func expect(_ text: String) -> Step { .expect(Array(text.utf8)) }
        public static func reply(_ text: String, delay: TimeInterval = 0) -> Step { .reply(Array(text.utf8), delay: delay) }
    }

    public nonisolated let identifier: String
    private var steps: [Step]
    private var nextStep = 0
    private var incoming: [UInt8] = []
    private var lastArrival = Date()

    public private(set) var isOpen = false
    public private(set) var writes: [[UInt8]] = []
    public private(set) var mismatches: [MockTransportMismatch] = []
    public private(set) var closeCount = 0

    public init(identifier: String = "/dev/cu.mock", script: [Step]) {
        self.identifier = identifier
        self.steps = script
    }

    /// `true` when every scripted step has been consumed.
    public var isScriptFinished: Bool { nextStep >= steps.count }

    public func open() async throws {
        try checkCancellation()
        isOpen = true
        lastArrival = Date()
        await deliverReplies()
    }

    public func write(_ bytes: [UInt8]) async throws {
        try checkCancellation()
        writes.append(bytes)
        guard nextStep < steps.count, case let .expect(expected) = steps[nextStep] else {
            let mismatch = MockTransportMismatch(stepIndex: nextStep, expected: nil, actual: bytes)
            mismatches.append(mismatch)
            throw mismatch
        }
        guard expected == bytes else {
            let mismatch = MockTransportMismatch(stepIndex: nextStep, expected: expected, actual: bytes)
            mismatches.append(mismatch)
            throw mismatch
        }
        nextStep += 1
        await deliverReplies()
    }

    public func read(count: Int, timeout: TimeInterval) async throws -> [UInt8] {
        try await waitUntil(timeout: timeout) { buffer in
            buffer.count >= count ? count : nil
        }
    }

    public func readUntil(_ terminator: [UInt8], maxLength: Int, timeout: TimeInterval) async throws -> [UInt8] {
        let line = try await waitUntil(timeout: timeout) { buffer in
            if let range = buffer.firstRange(of: terminator) {
                return range.upperBound
            }
            return nil
        }
        return Array(line.dropLast(terminator.count))
    }

    public func close() async {
        isOpen = false
        closeCount += 1
    }

    // MARK: - Internals

    private func deliverReplies() async {
        while nextStep < steps.count, case let .reply(bytes, delay) = steps[nextStep] {
            nextStep += 1
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            incoming.append(contentsOf: bytes)
            lastArrival = Date()
        }
    }

    /// Waits until `complete` returns the number of bytes to take from the buffer.
    private func waitUntil(timeout: TimeInterval, complete: ([UInt8]) -> Int?) async throws -> [UInt8] {
        lastArrival = max(lastArrival, Date().addingTimeInterval(-0.001))
        let start = Date()
        while true {
            try checkCancellation()
            guard isOpen else { throw LoggerError(.deviceNotFound, detail: "\(identifier) is not open") }
            if let take = complete(incoming) {
                let result = Array(incoming.prefix(take))
                incoming.removeFirst(take)
                return result
            }
            if Date().timeIntervalSince(max(start, lastArrival)) >= timeout {
                throw LoggerError(.timeout, detail: "\(identifier): no data for \(timeout) s")
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func checkCancellation() throws {
        if Task.isCancelled {
            throw LoggerError(.cancelled)
        }
    }
}
