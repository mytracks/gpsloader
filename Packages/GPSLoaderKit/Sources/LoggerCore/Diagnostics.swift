import Foundation

/// Metadata written at the start of a diagnostic capture.
public struct DiagnosticHeader: Sendable, Equatable {
    public var driver: String
    public var port: String?
    public var parameters: [String: String]

    public init(driver: String, port: String? = nil, parameters: [String: String] = [:]) {
        self.driver = driver
        self.port = port
        self.parameters = parameters
    }
}

/// One entry of a diagnostic capture (spec `diagnostic-capture`).
public enum DiagnosticEvent: Sendable, Equatable {
    case header(DiagnosticHeader)
    /// Bytes sent to the device.
    case transmitted(source: String, bytes: [UInt8])
    /// Bytes received from the device.
    case received(source: String, bytes: [UInt8])
    /// Something happened: open, close, timeout, cancel, error, ...
    case event(source: String, name: String, detail: String?)
}

/// Receives diagnostic events.
///
/// `record` is synchronous and must be cheap and thread safe, so that callers keep the exact
/// order of bytes on the wire without awaiting.
public protocol DiagnosticSink: Sendable {
    func record(_ event: DiagnosticEvent)
}

/// A sink that discards everything (diagnostic capture switched off).
public struct NullSink: DiagnosticSink {
    public init() {}
    public func record(_ event: DiagnosticEvent) {}
}

/// Common event names used with `DiagnosticEvent.event`.
public enum DiagnosticEventName {
    public static let open = "open"
    public static let close = "close"
    public static let timeout = "timeout"
    public static let cancel = "cancel"
    public static let error = "error"
}
