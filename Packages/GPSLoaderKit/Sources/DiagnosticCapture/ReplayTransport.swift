import Foundation
import LoggerCore

/// Raised when a driver deviates from a recorded dialog.
public struct ReplayMismatch: Error, Sendable, CustomStringConvertible {
    /// Index of the capture entry (0 = first line after the header).
    public var position: Int
    public var expected: [UInt8]?
    public var actual: [UInt8]

    public var description: String {
        let expectedText = expected.map { "\($0.hexString) (\($0.printableASCII))" } ?? "<end of capture>"
        return "Replay mismatch at position \(position): expected \(expectedText), got \(actual.hexString) (\(actual.printableASCII))"
    }
}

/// Plays back a recorded serial dialog as `ByteTransport` (spec `diagnostic-capture`, "Wiedergabe in Tests").
///
/// Recorded `tx` entries become expectations, `rx` entries become device replies. Replies before the
/// first `tx` are delivered on `open()`, the others after the matching write.
public actor ReplayTransport: ByteTransport {
    private struct Step: Sendable {
        var position: Int
        var isTransmit: Bool
        var bytes: [UInt8]
    }

    public nonisolated let identifier: String
    private let steps: [Step]
    private var nextStep = 0
    private var incoming: [UInt8] = []
    private var isOpen = false

    /// - Parameter source: only entries of this source are used (default: the first source with bytes).
    public init(entries: [CaptureLine], source: String? = nil) {
        let selectedSource = source ?? entries.first { $0.kind == "tx" || $0.kind == "rx" }?.source
        identifier = selectedSource ?? "replay"
        steps = entries.enumerated().compactMap { position, line in
            guard line.kind == "tx" || line.kind == "rx", line.source == selectedSource, let bytes = line.bytes else {
                return nil
            }
            return Step(position: position, isTransmit: line.kind == "tx", bytes: bytes)
        }
    }

    public init(captureData: Data, source: String? = nil) throws {
        self.init(entries: try CaptureFormat.decode(captureData).entries, source: source)
    }

    /// `true` when all recorded steps were used.
    public var isFinished: Bool { nextStep >= steps.count }

    public func open() async throws {
        isOpen = true
        deliverReplies()
    }

    public func write(_ bytes: [UInt8]) async throws {
        guard nextStep < steps.count, steps[nextStep].isTransmit else {
            throw ReplayMismatch(position: nextStep < steps.count ? steps[nextStep].position : steps.count,
                                 expected: nil, actual: bytes)
        }
        let step = steps[nextStep]
        guard step.bytes == bytes else {
            throw ReplayMismatch(position: step.position, expected: step.bytes, actual: bytes)
        }
        nextStep += 1
        deliverReplies()
    }

    public func read(count: Int, timeout: TimeInterval) async throws -> [UInt8] {
        try ensureOpen()
        guard incoming.count >= count else {
            throw LoggerError(.timeout, detail: "replay: \(count) bytes requested, \(incoming.count) recorded")
        }
        let bytes = Array(incoming.prefix(count))
        incoming.removeFirst(count)
        return bytes
    }

    public func readUntil(_ terminator: [UInt8], maxLength: Int, timeout: TimeInterval) async throws -> [UInt8] {
        try ensureOpen()
        guard let range = incoming.firstRange(of: terminator) else {
            throw LoggerError(.timeout, detail: "replay: terminator not in recorded data")
        }
        let line = Array(incoming[..<range.lowerBound])
        incoming.removeFirst(range.upperBound)
        return line
    }

    public func close() async {
        isOpen = false
    }

    private func deliverReplies() {
        while nextStep < steps.count, !steps[nextStep].isTransmit {
            incoming.append(contentsOf: steps[nextStep].bytes)
            nextStep += 1
        }
    }

    private func ensureOpen() throws {
        if Task.isCancelled { throw LoggerError(.cancelled) }
        guard isOpen else { throw LoggerError(.deviceNotFound, detail: "replay transport is not open") }
    }
}
