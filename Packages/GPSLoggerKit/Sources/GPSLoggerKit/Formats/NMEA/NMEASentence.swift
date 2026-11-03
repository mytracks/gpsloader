import Foundation

/// One syntactically checked NMEA 0183 sentence: `$<talker><type>,<fields>[*<checksum>]`.
struct NMEASentence {
    enum Validation {
        case valid(NMEASentence)
        /// The line is not an NMEA sentence at all (no `$`, proprietary, unsupported) and is ignored silently.
        case ignored
        case checksumMismatch
        case malformed
    }

    /// Two-letter talker (GP, GN, ...).
    let talker: Substring
    /// Three-letter sentence type (RMC, GGA, ...).
    let type: Substring
    /// Data fields after the address field (index 0 is the first data field).
    let fields: [Substring]

    /// Field `index`, or an empty string when the sentence is shorter.
    subscript(index: Int) -> Substring {
        index < fields.count ? fields[index] : ""
    }

    /// Checks a line (without line terminator). Lines not starting with `$` are ignored.
    static func validate(_ line: Substring) -> Validation {
        guard line.first == "$" else { return .ignored }
        var body = line.dropFirst()
        if let star = body.lastIndex(of: "*") {
            let checksumText = body[body.index(after: star)...].trimmingCharacters(in: .whitespaces)
            guard checksumText.count == 2, let expected = UInt8(checksumText, radix: 16) else { return .malformed }
            body = body[..<star]
            var actual: UInt8 = 0
            for byte in body.utf8 { actual ^= byte }
            guard actual == expected else { return .checksumMismatch }
        }
        var parts = body.split(separator: ",", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return .malformed }
        let address = parts.removeFirst()
        guard address.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) else { return .malformed }
        if address.first == "P" { return .ignored }  // proprietary sentence
        guard address.count == 5 else { return .ignored }
        let talker = address.prefix(2)
        let type = address.dropFirst(2)
        return .valid(NMEASentence(talker: talker, type: type, fields: parts))
    }

    // MARK: Field parsing

    /// `hhmmss[.sss]` as milliseconds since midnight.
    static func timeOfDay(_ field: Substring) -> Int? {
        let bytes = Array(field.utf8)
        guard bytes.count >= 6, bytes[0..<6].allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
        func digit(_ i: Int) -> Int { Int(bytes[i] - 0x30) }
        let hour = digit(0) * 10 + digit(1)
        let minute = digit(2) * 10 + digit(3)
        let second = digit(4) * 10 + digit(5)
        guard hour < 24, minute < 60, second < 61 else { return nil }
        var milliseconds = 0
        if bytes.count > 6 {
            guard bytes[6] == 0x2E else { return nil }
            var scale = 100
            for byte in bytes[7...] {
                guard byte >= 0x30, byte <= 0x39 else { return nil }
                milliseconds += Int(byte - 0x30) * scale
                scale /= 10
            }
        }
        return ((hour * 60 + minute) * 60 + second) * 1000 + milliseconds
    }

    enum CoordinateResult {
        case missing
        case invalid
        case value(Double)
    }

    /// `(d)ddmm.mmmm` plus hemisphere letter as signed degrees.
    static func coordinate(_ field: Substring, hemisphere: Substring, isLatitude: Bool) -> CoordinateResult {
        if field.isEmpty && hemisphere.isEmpty { return .missing }
        guard let raw = Double(field), raw >= 0 else { return .invalid }
        let degrees = (raw / 100).rounded(.down)
        let minutes = raw - degrees * 100
        guard minutes < 60 else { return .invalid }
        var value = degrees + minutes / 60
        let positive: Substring = isLatitude ? "N" : "E"
        let negative: Substring = isLatitude ? "S" : "W"
        if hemisphere == negative {
            value = -value
        } else if hemisphere != positive {
            return .invalid
        }
        guard abs(value) <= (isLatitude ? 90 : 180) else { return .invalid }
        return .value(value)
    }

    static func double(_ field: Substring) -> Double? {
        field.isEmpty ? nil : Double(field)
    }

    static func int(_ field: Substring) -> Int? {
        field.isEmpty ? nil : Int(field)
    }
}
