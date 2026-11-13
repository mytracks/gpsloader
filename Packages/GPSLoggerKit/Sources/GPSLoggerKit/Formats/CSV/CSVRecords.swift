import Foundation

/// Line and field splitting for the comma separated logger formats (spec `csv-logger-import`).
///
/// Fields are split at every comma (there is no quoting in these formats) and trimmed of spaces,
/// tabs, NUL padding and a byte order mark. Lines whose fields are all empty are skipped.
enum CSVRecords {
    /// Calls `body` with the 1-based line number and trimmed fields of every non-empty line.
    /// `body` returns `false` to stop.
    static func forEachRecord(in data: Data, _ body: (Int, [Substring]) throws -> Bool) rethrows {
        try TextLines.forEachLine(in: data, where: { _ in true }) { number, line in
            let fields = fields(of: line)
            if fields.allSatisfy(\.isEmpty) { return true }
            return try body(number, fields)
        }
    }

    /// The header of the first non-empty line, if any.
    static func header(in data: Data) -> CSVHeader? {
        var header: CSVHeader?
        forEachRecord(in: data) { _, fields in
            header = CSVHeader(fields)
            return false
        }
        return header
    }

    static func fields(of line: Substring) -> [Substring] {
        line.split(separator: ",", omittingEmptySubsequences: false).map(trimmed)
    }

    static func trimmed(_ field: Substring) -> Substring {
        let isPadding: (Character) -> Bool = { $0 == " " || $0 == "\t" || $0 == "\0" || $0 == "\u{FEFF}" }
        guard let first = field.firstIndex(where: { !isPadding($0) }),
              let last = field.lastIndex(where: { !isPadding($0) }) else { return field[field.endIndex...] }
        return field[first...last]
    }

    /// A finite number, or `nil` for an empty or unreadable field.
    static func number(_ field: Substring?) -> Double? {
        guard let field, !field.isEmpty, let value = Double(field), value.isFinite else { return nil }
        return value
    }

    /// A non-negative integer made of ASCII digits only.
    static func digits(_ field: Substring) -> Int? {
        guard !field.isEmpty, field.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
        return Int(field)
    }
}

/// The column names of a header line, upper-cased. A trailing empty field (line ending in a comma)
/// is not a column.
struct CSVHeader: Equatable {
    let names: [String]

    init(_ fields: [Substring]) {
        var names = fields.map { $0.uppercased() }
        if names.count > 1, names.last?.isEmpty == true { names.removeLast() }
        self.names = names
    }

    func column(_ name: String) -> Int? {
        names.firstIndex(of: name)
    }

    func column(prefix: String) -> Int? {
        names.firstIndex { $0.hasPrefix(prefix) }
    }
}

extension Array where Element == Substring {
    /// The field at `index`, or `nil` if there is no such column, the line is too short or the field is empty.
    subscript(field index: Int?) -> Substring? {
        guard let index, index < count, !self[index].isEmpty else { return nil }
        return self[index]
    }
}

/// Values shared by both CSV logger formats.
enum CSVValues {
    /// Speed in km/h as meters per second.
    static func speed(_ field: Substring?) -> Double? {
        CSVRecords.number(field).flatMap { $0 >= 0 ? $0 / 3.6 : nil }
    }

    static func course(_ field: Substring?) -> Double? {
        CSVRecords.number(field).flatMap { (0...360).contains($0) ? $0 : nil }
    }

    /// A dilution of precision; 0 means "unknown".
    static func dop(_ field: Substring?) -> Double? {
        CSVRecords.number(field).flatMap { $0 > 0 ? $0 : nil }
    }

    /// Applies the hemisphere to a magnitude and checks the range.
    /// - Returns: `nil` when the hemisphere is invalid; `.outOfRange` when the magnitude is too large.
    static func coordinate(magnitude: Double, hemisphere: Character, positive: Character, negative: Character,
                           limit: Double) -> CoordinateValue? {
        let sign: Double
        switch hemisphere {
        case positive: sign = 1
        case negative: sign = -1
        default: return nil
        }
        guard magnitude <= limit else { return .outOfRange }
        return .value(sign * magnitude)
    }

    enum CoordinateValue: Equatable {
        case value(Double)
        case outOfRange
    }
}
