import Foundation

/// Why reading or writing a file failed.
public enum GPSLoggerErrorKind: Sendable, Hashable {
    /// The file could not be read at all.
    case unreadable
    /// The file has no content.
    case empty
    /// The file is structurally broken (e.g. not well-formed XML) at the given line, if known.
    case malformed(line: Int?)
    /// The file was read but contains no usable track point or waypoint.
    case noUsableData
    /// A GPX file could not be written.
    case writeFailed

    /// Stable key used for localization.
    public var key: String {
        switch self {
        case .unreadable: "unreadable"
        case .empty: "empty"
        case .malformed: "malformed"
        case .noUsableData: "noUsableData"
        case .writeFailed: "writeFailed"
        }
    }

    /// One representative of every kind, for tests and documentation.
    public static let allKeys = ["unreadable", "empty", "malformed", "noUsableData", "writeFailed"]
}

/// A user presentable error with a localized message.
public struct GPSLoggerError: Error, Sendable, Hashable, LocalizedError {
    public var kind: GPSLoggerErrorKind
    /// Name of the affected file.
    public var fileName: String
    /// Technical detail (system error text, parser message). Not localized.
    public var detail: String

    public init(_ kind: GPSLoggerErrorKind, fileName: String, detail: String = "") {
        self.kind = kind
        self.fileName = fileName
        self.detail = detail
    }

    public var errorDescription: String? {
        Self.message(for: kind, fileName: fileName)
    }

    public var failureReason: String? {
        detail.isEmpty ? nil : detail
    }

    /// Localized message, e.g. "“track.gpx” is not well-formed (line 12)."
    /// - Parameter localization: a specific localization ("de", "en") or `nil` for the preferred language.
    public static func message(for kind: GPSLoggerErrorKind, fileName: String, localization: String? = nil) -> String {
        let format = LocalizedStrings.string("error.\(kind.key)", localization: localization)
        var text = String(format: format, fileName)
        if case .malformed(let line?) = kind {
            text += " " + String(format: LocalizedStrings.string("error.line", localization: localization), line)
        }
        return text
    }
}

/// What kind of problem was skipped while reading.
public enum ImportWarningKind: String, Sendable, Hashable, CaseIterable {
    /// An NMEA sentence with a wrong checksum.
    case checksumMismatch
    /// A record that could not be parsed.
    case malformedRecord
    /// A position outside the valid range.
    case invalidCoordinate
    /// Points without a date; they have no time.
    case missingDate
}

/// A summarized, non-fatal problem: how often it occurred in which file, and where first.
public struct ImportWarning: Sendable, Hashable {
    public var kind: ImportWarningKind
    public var count: Int
    public var fileName: String
    /// Line (or record number) of the first occurrence, if known.
    public var firstLine: Int?

    public init(kind: ImportWarningKind, count: Int, fileName: String, firstLine: Int? = nil) {
        self.kind = kind
        self.count = count
        self.fileName = fileName
        self.firstLine = firstLine
    }

    /// Localized description, e.g. "3 records with a wrong checksum were skipped in “a.nmea”."
    public func message(localization: String? = nil) -> String {
        let format = LocalizedStrings.string("warning.\(kind.rawValue)", localization: localization)
        return String(format: format, count, fileName)
    }
}

/// Collects warnings per kind while a file is read.
struct WarningCollector {
    let fileName: String
    private var entries: [ImportWarningKind: (count: Int, firstLine: Int?)] = [:]

    init(fileName: String) {
        self.fileName = fileName
    }

    mutating func add(_ kind: ImportWarningKind, line: Int?, count: Int = 1) {
        if let entry = entries[kind] {
            entries[kind] = (entry.count + count, entry.firstLine)
        } else {
            entries[kind] = (count, line)
        }
    }

    var warnings: [ImportWarning] {
        ImportWarningKind.allCases.compactMap { kind in
            entries[kind].map { ImportWarning(kind: kind, count: $0.count, fileName: fileName, firstLine: $0.firstLine) }
        }
    }
}

/// Access to the localized strings of this module.
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
