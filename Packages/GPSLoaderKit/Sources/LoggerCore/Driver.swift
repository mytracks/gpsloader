import Foundation

/// Progress of a running operation (spec `logger-session`, "Fortschritt").
public enum ProgressUpdate: Sendable, Equatable {
    /// `completed` of `total` units (points, bytes, blocks, ...) are done.
    case determinate(completed: Int, total: Int, step: String?)
    /// The total is unknown; `step` describes what is happening.
    case indeterminate(step: String)

    /// Fraction between 0 and 1, or `nil` for indeterminate progress.
    public var fraction: Double? {
        switch self {
        case let .determinate(completed, total, _):
            guard total > 0 else { return nil }
            return min(max(Double(completed) / Double(total), 0), 1)
        case .indeterminate:
            return nil
        }
    }

    public var step: String? {
        switch self {
        case let .determinate(_, _, step): step
        case let .indeterminate(step): step
        }
    }
}

/// Whether and how a driver can erase the logger memory.
public enum EraseSupport: Sendable, Equatable {
    case unsupported
    case supported
    /// Supported, but not verified with real hardware (e.g. i-GotU). The user must be warned.
    case experimental
}

/// Static description of a driver.
public struct DriverDescriptor: Sendable, Equatable {
    /// Stable identifier, e.g. "bg728" or "gpsbabel.mtk".
    public var id: String
    /// Display name of the device or device family.
    public var name: String
    public var eraseSupport: EraseSupport
    /// The operation fails with `.timeout` if the driver reports no activity for this long.
    public var activityTimeout: TimeInterval

    public init(id: String, name: String, eraseSupport: EraseSupport, activityTimeout: TimeInterval = 30) {
        self.id = id
        self.name = name
        self.eraseSupport = eraseSupport
        self.activityTimeout = activityTimeout
    }
}

/// Everything a driver gets from the session while it runs.
public struct DriverContext: Sendable {
    /// Report progress. Every report also counts as activity for the session watchdog.
    public let progress: @Sendable (ProgressUpdate) -> Void
    /// Signal activity without a visible progress change (e.g. a received chunk).
    public let activity: @Sendable () -> Void
    /// Where to send diagnostic events.
    public let diagnostics: any DiagnosticSink

    public init(progress: @escaping @Sendable (ProgressUpdate) -> Void = { _ in },
                activity: @escaping @Sendable () -> Void = {},
                diagnostics: any DiagnosticSink = NullSink()) {
        self.progress = progress
        self.activity = activity
        self.diagnostics = diagnostics
    }
}

/// The contract every driver implements (spec `logger-session`, "Einheitlicher Treibervertrag").
///
/// Drivers receive their transport (or gpsbabel runner) when they are created and must
/// react to task cancellation by throwing `LoggerError(.cancelled)` or `CancellationError`.
public protocol LoggerDriver: Sendable {
    var descriptor: DriverDescriptor { get }

    /// The resource the driver uses exclusively, e.g. the port path. Used to prevent two
    /// operations on the same device at the same time.
    var resourceKey: String { get }

    /// Reads all data from the device.
    func read(_ context: DriverContext) async throws -> Recording

    /// Erases the logger memory. Only called when `descriptor.eraseSupport` is not `.unsupported`
    /// and the user has confirmed.
    func erase(_ context: DriverContext) async throws
}

extension LoggerDriver {
    public func erase(_ context: DriverContext) async throws {
        throw LoggerError(.protocolError, detail: "Erasing is not supported by \(descriptor.name).")
    }
}
