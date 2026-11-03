import Foundation
import LoggerCore

/// Wraps any `ByteTransport` and reports every byte and event to a `DiagnosticSink`.
///
/// For `readUntil` the received bytes are recorded *including* the terminator, so a replay
/// delivers exactly what came over the wire.
public struct CapturingTransport: ByteTransport {
    public let base: any ByteTransport
    public let sink: any DiagnosticSink

    public init(_ base: any ByteTransport, sink: any DiagnosticSink) {
        self.base = base
        self.sink = sink
    }

    public var identifier: String { base.identifier }

    public func open() async throws {
        do {
            try await base.open()
            sink.record(.event(source: identifier, name: DiagnosticEventName.open, detail: nil))
        } catch {
            recordFailure(error)
            throw error
        }
    }

    public func write(_ bytes: [UInt8]) async throws {
        sink.record(.transmitted(source: identifier, bytes: bytes))
        do {
            try await base.write(bytes)
        } catch {
            recordFailure(error)
            throw error
        }
    }

    public func read(count: Int, timeout: TimeInterval) async throws -> [UInt8] {
        do {
            let bytes = try await base.read(count: count, timeout: timeout)
            sink.record(.received(source: identifier, bytes: bytes))
            return bytes
        } catch {
            recordFailure(error)
            throw error
        }
    }

    public func readUntil(_ terminator: [UInt8], maxLength: Int, timeout: TimeInterval) async throws -> [UInt8] {
        do {
            let bytes = try await base.readUntil(terminator, maxLength: maxLength, timeout: timeout)
            sink.record(.received(source: identifier, bytes: bytes + terminator))
            return bytes
        } catch {
            recordFailure(error)
            throw error
        }
    }

    public func close() async {
        await base.close()
        sink.record(.event(source: identifier, name: DiagnosticEventName.close, detail: nil))
    }

    private func recordFailure(_ error: any Error) {
        let name: String
        var detail = String(describing: error)
        if let loggerError = error as? LoggerError {
            switch loggerError.kind {
            case .timeout: name = DiagnosticEventName.timeout
            case .cancelled: name = DiagnosticEventName.cancel
            default: name = DiagnosticEventName.error
            }
            detail = "\(loggerError.kind.rawValue): \(loggerError.detail)"
        } else {
            name = DiagnosticEventName.error
        }
        sink.record(.event(source: identifier, name: name, detail: detail))
    }
}
