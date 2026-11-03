import Foundation

/// App-wide registry that ensures only one operation uses a port or device at a time
/// (spec `logger-session`, "Nur ein Vorgang gleichzeitig").
public actor PortReservations {
    private var reserved: Set<String> = []

    public init() {}

    /// Reserves `key`. Returns `false` if it is already in use.
    public func reserve(_ key: String) -> Bool {
        reserved.insert(key).inserted
    }

    public func release(_ key: String) {
        reserved.remove(key)
    }

    public func isReserved(_ key: String) -> Bool {
        reserved.contains(key)
    }
}
