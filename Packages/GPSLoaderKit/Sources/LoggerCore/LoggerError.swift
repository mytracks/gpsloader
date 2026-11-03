import Foundation

/// The kinds of errors an operation on a logger can end with (spec `logger-session`).
public enum LoggerErrorKind: String, Sendable, CaseIterable {
    case deviceNotFound
    case portBusy
    case timeout
    case protocolError
    case rosettaMissing
    case gpsbabelFailed
    case writeFailed
    case cancelled
}

/// A user presentable error with a localized message and a technical detail.
public struct LoggerError: Error, Sendable, Equatable, LocalizedError {
    public var kind: LoggerErrorKind
    /// Technical detail (port name, gpsbabel stderr, errno text, ...). Not localized.
    public var detail: String

    public init(_ kind: LoggerErrorKind, detail: String = "") {
        self.kind = kind
        self.detail = detail
    }

    public var errorDescription: String? {
        Self.message(for: kind)
    }

    public var failureReason: String? {
        detail.isEmpty ? nil : detail
    }

    public var recoverySuggestion: String? {
        Self.recoverySuggestion(for: kind)
    }

    /// Localized message for an error kind.
    /// - Parameter localization: a specific localization ("de", "en") or `nil` for the user's preferred language.
    public static func message(for kind: LoggerErrorKind, localization: String? = nil) -> String {
        LocalizedStrings.string("error.\(kind.rawValue).message", localization: localization)
    }

    /// Localized recovery suggestion for an error kind, if there is one.
    public static func recoverySuggestion(for kind: LoggerErrorKind, localization: String? = nil) -> String? {
        let key = "error.\(kind.rawValue).recovery"
        let value = LocalizedStrings.string(key, localization: localization)
        return value == key || value.isEmpty ? nil : value
    }
}

/// Access to the localized strings of the LoggerCore module.
enum LocalizedStrings {
    static func string(_ key: String, localization: String? = nil) -> String {
        if let localization,
           let path = Bundle.module.path(forResource: localization, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: key, table: nil)
        }
        return Bundle.module.localizedString(forKey: key, value: key, table: nil)
    }
}
