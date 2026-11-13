import Foundation

/// IGC flight recorder files (spec `igc-import`), read according to the FAI/IGC
/// "Technical Specification for IGC-approved GNSS Flight Recorders", Appendix A.
///
/// Every file becomes one track named after the file. Only B (fix), I (B extensions) and
/// H…DTE (date) records are evaluated; all other records are ignored.
public struct IGCFileFormat: FileFormat {
    public init() {}

    public var id: FileFormatID { .igc }
    public var displayName: String { LocalizedStrings.string("format.igc") }
    public var fileExtensions: [String] { ["igc"] }

    /// The first non-empty line is an A record (`A` plus three letters or digits), and a later line
    /// of the prefix is an H or B record.
    public func matches(prefix: Data) -> Bool {
        var isFirst = true
        for line in TextLines.lines(of: prefix, where: { _ in true }) {
            let text = line.text.trimmingCharacters(in: .whitespaces)
            guard let first = text.utf8.first else { continue }
            if isFirst {
                isFirst = false
                let bytes = Array(text.utf8)
                guard bytes.count >= 4, first == IGCRecord.a,
                      bytes[1...3].allSatisfy(IGCRecord.isAlphanumeric) else { return false }
                continue
            }
            if first == IGCRecord.h || first == IGCRecord.b { return true }
        }
        return false
    }

    public func read(_ inputs: [FileInput]) throws -> ImportResult {
        var tracks: [Track] = []
        var warnings: [ImportWarning] = []
        for input in inputs {
            var reader = IGCFileReader(fileName: input.name)
            try reader.read(input.data)
            if !reader.points.isEmpty {
                tracks.append(Track(name: Self.trackName(for: input.name), segments: [TrackSegment(points: reader.points)]))
            }
            warnings += reader.warnings.warnings
        }
        return ImportResult(recording: Recording(tracks: tracks), warnings: warnings)
    }

    /// The file name without directory and extension, e.g. "flight1" for "flight1.igc".
    static func trackName(for fileName: String) -> String {
        baseName(ofFile: fileName)
    }
}

/// Record type letters and byte helpers.
enum IGCRecord {
    static let a: UInt8 = 0x41  // "A"
    static let b: UInt8 = 0x42  // "B"
    static let h: UInt8 = 0x48  // "H"
    static let i: UInt8 = 0x49  // "I"

    static func isAlphanumeric(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
    }

    /// The decimal number in `bytes[from..<from+length]`, or `nil` if any byte is not a digit or the range is too short.
    static func number(_ bytes: [UInt8], _ from: Int, _ length: Int) -> Int? {
        guard from >= 0, length > 0, from + length <= bytes.count else { return nil }
        var value = 0
        for byte in bytes[from..<(from + length)] {
            guard byte >= 0x30, byte <= 0x39 else { return nil }
            value = value * 10 + Int(byte - 0x30)
        }
        return value
    }

    /// Like `number`, but the first byte may be `-`.
    static func signedNumber(_ bytes: [UInt8], _ from: Int, _ length: Int) -> Int? {
        guard from < bytes.count else { return nil }
        if bytes[from] == 0x2D {  // "-"
            return number(bytes, from + 1, length - 1).map { -$0 }
        }
        return number(bytes, from, length)
    }
}

/// Reads one IGC file.
struct IGCFileReader {
    private(set) var points: [TrackPoint] = []
    var warnings: WarningCollector

    /// A B record extension announced by the I record; `start` and `end` are 0-based, `end` exclusive.
    private struct Extension {
        var start: Int
        var end: Int
        var code: String
    }

    private var extensions: [Extension] = []
    /// Days since 1970 from the H…DTE record.
    private var date: Int?
    /// Days added because the time of day went backwards (midnight).
    private var dayOffset = 0
    private var lastSecondOfDay: Int?
    private var undated = 0

    /// Length of a B record without extensions.
    static let fixLength = 35

    init(fileName: String) {
        warnings = WarningCollector(fileName: fileName)
    }

    mutating func read(_ data: Data) throws {
        var cancellation = CancellationCheck()
        let relevant: (UInt8) -> Bool = { $0 == IGCRecord.b || $0 == IGCRecord.i || $0 == IGCRecord.h }
        try TextLines.forEachLine(in: data, where: relevant) { number, line in
            try cancellation.tick()
            let bytes = Array(line.utf8)
            switch bytes[0] {
            case IGCRecord.b: fix(bytes, line: number)
            case IGCRecord.i: extensionsRecord(bytes, line: number)
            default: header(bytes, line: number)
            }
            return true
        }
        if undated > 0 { warnings.add(.missingDate, line: nil, count: undated) }
    }

    // MARK: Records

    /// `H` + source + `DTE` followed by `ddmmyy` or `DATE:ddmmyy[,nn]`.
    private mutating func header(_ bytes: [UInt8], line: Int) {
        guard bytes.count >= 5, bytes[2...4].elementsEqual("DTE".utf8) else { return }
        var start = 5
        if let colon = bytes[5...].firstIndex(of: 0x3A) { start = colon + 1 }  // ":"
        guard start + 6 <= bytes.count,
              let days = UTCTime.days(ddmmyy: String(decoding: bytes[start..<(start + 6)], as: UTF8.self)) else {
            return warnings.add(.malformedRecord, line: line)
        }
        date = days
        dayOffset = 0
    }

    /// `I` + count `NN` + count × (start `SS`, finish `FF`, code `CCC`), positions 1-based.
    private mutating func extensionsRecord(_ bytes: [UInt8], line: Int) {
        extensions = []
        guard let count = IGCRecord.number(bytes, 1, 2), bytes.count >= 3 + 7 * count else {
            return warnings.add(.malformedRecord, line: line)
        }
        var parsed: [Extension] = []
        for k in 0..<count {
            let offset = 3 + 7 * k
            guard let start = IGCRecord.number(bytes, offset, 2), let finish = IGCRecord.number(bytes, offset + 2, 2),
                  start >= 1, finish >= start else {
                return warnings.add(.malformedRecord, line: line)
            }
            let code = String(decoding: bytes[(offset + 4)..<(offset + 7)], as: UTF8.self)
            parsed.append(Extension(start: start - 1, end: finish, code: code))
        }
        extensions = parsed
    }

    /// `B HHMMSS DDMMmmm N DDDMMmmm E V PPPPP GGGGG` + extensions.
    private mutating func fix(_ bytes: [UInt8], line: Int) {
        guard bytes.count >= Self.fixLength,
              let hour = IGCRecord.number(bytes, 1, 2), let minute = IGCRecord.number(bytes, 3, 2),
              let second = IGCRecord.number(bytes, 5, 2), hour < 24, minute < 60, second < 60,
              let latDegrees = IGCRecord.number(bytes, 7, 2), let latMinutes = IGCRecord.number(bytes, 9, 5),
              let lonDegrees = IGCRecord.number(bytes, 15, 3), let lonMinutes = IGCRecord.number(bytes, 18, 5),
              bytes[14] == 0x4E || bytes[14] == 0x53,  // N, S
              bytes[23] == 0x45 || bytes[23] == 0x57,  // E, W
              bytes[24] == 0x41 || bytes[24] == 0x56,  // A, V
              let pressureAltitude = IGCRecord.signedNumber(bytes, 25, 5),
              let gnssAltitude = IGCRecord.signedNumber(bytes, 30, 5) else {
            return warnings.add(.malformedRecord, line: line)
        }
        var latitude = Double(latDegrees) + Double(latMinutes) / 60_000
        var longitude = Double(lonDegrees) + Double(lonMinutes) / 60_000
        guard latMinutes < 60_000, lonMinutes < 60_000, latitude <= 90, longitude <= 180 else {
            return warnings.add(.invalidCoordinate, line: line)
        }
        if bytes[14] == 0x53 { latitude = -latitude }
        if bytes[23] == 0x57 { longitude = -longitude }

        let valid = bytes[24] == 0x41
        let elevation: Double? = if valid && gnssAltitude != 0 {
            Double(gnssAltitude)
        } else if pressureAltitude != 0 {
            Double(pressureAltitude)
        } else {
            nil
        }

        var quality = PositionQuality()
        quality.fix = valid ? .threeD : .twoD
        if let siu = extensions.first(where: { $0.code == "SIU" }) {
            quality.satellites = IGCRecord.number(bytes, siu.start, siu.end - siu.start)
        }

        let secondOfDay = (hour * 60 + minute) * 60 + second
        if let last = lastSecondOfDay, secondOfDay < last { dayOffset += 1 }
        lastSecondOfDay = secondOfDay

        var time: Date?
        if let date {
            time = UTCTime.date(days: date + dayOffset, timeOfDay: secondOfDay * 1000)
        } else {
            undated += 1
        }
        points.append(TrackPoint(latitude: latitude, longitude: longitude, elevation: elevation, time: time,
                                 quality: quality))
    }
}
