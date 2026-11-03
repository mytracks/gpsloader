import Foundation

/// Minimal lock-protected box for mutable state at system boundaries
/// (callbacks from Dispatch, Process handlers, IOKit notifications).
///
/// macOS 12 offers neither `Mutex` (macOS 15) nor `OSAllocatedUnfairLock` (macOS 13),
/// so this wraps `NSLock`. All access goes through `withLock`, which makes the
/// `@unchecked Sendable` conformance sound. Everywhere else, prefer actors.
public final class Locked<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    public init(_ value: Value) {
        self.value = value
    }

    @discardableResult
    public func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }

    /// A copy of the current value.
    public var current: Value {
        withLock { $0 }
    }
}
