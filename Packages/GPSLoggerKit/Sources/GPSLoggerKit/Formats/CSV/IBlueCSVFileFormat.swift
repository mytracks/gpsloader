import Foundation

/// CSV exports of iBlue 747/757 (MTK) loggers (spec `csv-logger-import`). Columns are found by the names
/// in the header line, so their order and additional columns do not matter.
///
/// Every file becomes one track named after the file.
public struct IBlueCSVFileFormat: FileFormat {
    public init() {}

    public var id: FileFormatID { .iblueCSV }
    public var displayName: String { LocalizedStrings.string("format.iblue-csv") }
    public var fileExtensions: [String] { ["csv"] }

    /// Columns every header must contain; the first column must be `INDEX`.
    static let requiredColumns = ["DATE", "TIME", "LATITUDE", "N/S", "LONGITUDE", "E/W"]

    static func isHeader(_ header: CSVHeader) -> Bool {
        header.names.first == "INDEX" && requiredColumns.allSatisfy(header.names.contains)
    }

    public func matches(prefix: Data) -> Bool {
        CSVRecords.header(in: prefix).map(Self.isHeader) ?? false
    }

    public func read(_ inputs: [FileInput]) throws -> ImportResult {
        var tracks: [Track] = []
        var warnings: [ImportWarning] = []
        for input in inputs {
            var reader = IBlueCSVFileReader(fileName: input.name)
            try reader.read(input.data)
            if !reader.points.isEmpty {
                tracks.append(Track(name: baseName(ofFile: input.name), segments: [TrackSegment(points: reader.points)]))
            }
            warnings += reader.warnings.warnings
        }
        return ImportResult(recording: Recording(tracks: tracks), warnings: warnings)
    }
}

/// Reads one iBlue CSV file.
struct IBlueCSVFileReader {
    private(set) var points: [TrackPoint] = []
    var warnings: WarningCollector
    private let fileName: String

    private struct Columns {
        var date: Int, time: Int, latitude: Int, north: Int, longitude: Int, east: Int
        var valid: Int?, height: Int?, speed: Int?, heading: Int?, pdop: Int?, hdop: Int?, vdop: Int?, satellites: Int?

        init?(_ header: CSVHeader) {
            guard IBlueCSVFileFormat.isHeader(header),
                  let date = header.column("DATE"), let time = header.column("TIME"),
                  let latitude = header.column("LATITUDE"), let north = header.column("N/S"),
                  let longitude = header.column("LONGITUDE"), let east = header.column("E/W") else { return nil }
            self.date = date
            self.time = time
            self.latitude = latitude
            self.north = north
            self.longitude = longitude
            self.east = east
            valid = header.column("VALID")
            height = header.column("HEIGHT")
            speed = header.column("SPEED")
            heading = header.column("HEADING")
            pdop = header.column("PDOP")
            hdop = header.column("HDOP")
            vdop = header.column("VDOP")
            satellites = header.column(prefix: "NSAT")
        }
    }

    init(fileName: String) {
        self.fileName = fileName
        warnings = WarningCollector(fileName: fileName)
    }

    mutating func read(_ data: Data) throws {
        var cancellation = CancellationCheck()
        var columns: Columns?
        try CSVRecords.forEachRecord(in: data) { number, fields in
            try cancellation.tick()
            if let columns {
                row(fields, columns: columns, line: number)
            } else {
                guard let parsed = Columns(CSVHeader(fields)) else {
                    throw GPSLoggerError(.malformed(line: 1), fileName: fileName)
                }
                columns = parsed
            }
            return true
        }
        if columns == nil { throw GPSLoggerError(.malformed(line: 1), fileName: fileName) }
    }

    private mutating func row(_ fields: [Substring], columns c: Columns, line: Int) {
        guard let dateField = fields[field: c.date], let timeField = fields[field: c.time],
              let time = Self.time(date: dateField, time: timeField),
              let latitude = Self.coordinate(fields[field: c.latitude], fields[field: c.north],
                                             positive: "N", negative: "S", limit: 90),
              let longitude = Self.coordinate(fields[field: c.longitude], fields[field: c.east],
                                              positive: "E", negative: "W", limit: 180) else {
            return warnings.add(.malformedRecord, line: line)
        }
        guard case .value(let lat) = latitude, case .value(let lon) = longitude else {
            return warnings.add(.invalidCoordinate, line: line)
        }

        var quality = PositionQuality()
        quality.speed = CSVValues.speed(fields[field: c.speed])
        quality.course = CSVValues.course(fields[field: c.heading])
        quality.pdop = CSVValues.dop(fields[field: c.pdop])
        quality.hdop = CSVValues.dop(fields[field: c.hdop])
        quality.vdop = CSVValues.dop(fields[field: c.vdop])
        quality.satellites = Self.satellites(fields[field: c.satellites])
        switch fields[field: c.valid]?.lowercased() {
        case "2d": quality.fix = .twoD
        case "3d": quality.fix = .threeD
        case "dgps": quality.fix = .dgps
        default: break
        }
        points.append(TrackPoint(latitude: lat, longitude: lon, elevation: CSVRecords.number(fields[field: c.height]),
                                 time: time, quality: quality))
    }

    /// `YYYY/MM/DD` or `DD/MM/YYYY`, and `hh:mm:ss[.fff]`, UTC; rounded to milliseconds.
    static func time(date: Substring, time: Substring) -> Date? {
        let parts = date.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, let a = CSVRecords.digits(parts[0]), let b = CSVRecords.digits(parts[1]),
              let c = CSVRecords.digits(parts[2]) else { return nil }
        let (year, month, day): (Int, Int, Int)
        if parts[0].count == 4 {
            (year, month, day) = (a, b, c)
        } else if parts[2].count == 4 {
            (year, month, day) = (c, b, a)
        } else {
            return nil
        }

        let clock = time.split(separator: ":", omittingEmptySubsequences: false)
        guard clock.count == 3, let hour = CSVRecords.digits(clock[0]), let minute = CSVRecords.digits(clock[1]),
              let second = Self.seconds(clock[2]) else { return nil }
        return UTCTime.date(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    }

    /// `ss` or `ss.f…`, rounded to milliseconds.
    private static func seconds(_ field: Substring) -> Double? {
        let parts = field.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, let whole = CSVRecords.digits(parts[0]) else { return nil }
        guard parts.count == 2 else { return Double(whole) }
        guard CSVRecords.digits(parts[1]) != nil, let value = Double(field) else { return nil }
        return (value * 1000).rounded() / 1000
    }

    /// The magnitude of the number with the sign of the hemisphere.
    static func coordinate(_ value: Substring?, _ hemisphere: Substring?, positive: Character, negative: Character,
                           limit: Double) -> CSVValues.CoordinateValue? {
        guard let magnitude = CSVRecords.number(value).map(abs),
              let hemisphere, hemisphere.count == 1, let letter = hemisphere.uppercased().first else { return nil }
        return CSVValues.coordinate(magnitude: magnitude, hemisphere: letter, positive: positive, negative: negative,
                                    limit: limit)
    }

    /// The leading digits, e.g. 7 for `7(10)`; a leading minus means "unknown".
    static func satellites(_ field: Substring?) -> Int? {
        guard let field else { return nil }
        let digits = field.prefix { $0.isASCII && $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }
}
