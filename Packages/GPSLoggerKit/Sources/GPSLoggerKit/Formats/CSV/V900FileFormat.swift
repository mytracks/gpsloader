import Foundation

/// CSV logs of the Columbus V-900 and Visiontac VGPS-900 (spec `csv-logger-import`), in simple and
/// professional mode. Fields are fixed width and NUL padded on the device; they are read at the commas.
///
/// Every file becomes one track named after the file. Rows tagged as a point of interest or a voice
/// recording additionally become waypoints.
public struct V900FileFormat: FileFormat {
    public init() {}

    public var id: FileFormatID { .v900 }
    public var displayName: String { LocalizedStrings.string("format.v900") }
    public var fileExtensions: [String] { ["csv"] }

    /// The leading columns every V-900 header starts with.
    static let requiredColumns = ["INDEX", "TAG", "DATE", "TIME", "LATITUDE N/S", "LONGITUDE E/W"]

    public func matches(prefix: Data) -> Bool {
        guard let header = CSVRecords.header(in: prefix) else { return false }
        return header.names.starts(with: Self.requiredColumns)
    }

    public func read(_ inputs: [FileInput]) throws -> ImportResult {
        var recording = Recording()
        var warnings: [ImportWarning] = []
        for input in inputs {
            var reader = V900FileReader(fileName: input.name)
            try reader.read(input.data)
            if !reader.points.isEmpty {
                recording.tracks.append(Track(name: baseName(ofFile: input.name),
                                              segments: [TrackSegment(points: reader.points)]))
            }
            recording.waypoints += reader.waypoints
            warnings += reader.warnings.warnings
        }
        return ImportResult(recording: recording, warnings: warnings)
    }
}

/// Reads one V-900 file.
struct V900FileReader {
    private(set) var points: [TrackPoint] = []
    private(set) var waypoints: [Waypoint] = []
    var warnings: WarningCollector
    private let fileName: String
    private var markers = 0

    private struct Columns {
        var tag = 1, date = 2, time = 3, latitude = 4, longitude = 5
        var height: Int?, speed: Int?, heading: Int?, fixMode: Int?, valid: Int?
        var pdop: Int?, hdop: Int?, vdop: Int?, vox: Int?

        init(_ header: CSVHeader) {
            height = header.column("HEIGHT")
            speed = header.column("SPEED")
            heading = header.column("HEADING")
            fixMode = header.column("FIX MODE")
            valid = header.column("VALID")
            pdop = header.column("PDOP")
            hdop = header.column("HDOP")
            vdop = header.column("VDOP")
            vox = header.column("VOX")
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
                let header = CSVHeader(fields)
                guard header.names.starts(with: V900FileFormat.requiredColumns) else {
                    throw GPSLoggerError(.malformed(line: 1), fileName: fileName)
                }
                columns = Columns(header)
            }
            return true
        }
        if columns == nil { throw GPSLoggerError(.malformed(line: 1), fileName: fileName) }
    }

    private mutating func row(_ fields: [Substring], columns c: Columns, line: Int) {
        guard let dateField = fields[field: c.date], let timeField = fields[field: c.time],
              let time = Self.time(date: dateField, time: timeField),
              let latitudeField = fields[field: c.latitude], let longitudeField = fields[field: c.longitude],
              let latitude = Self.coordinate(latitudeField, positive: "N", negative: "S", limit: 90),
              let longitude = Self.coordinate(longitudeField, positive: "E", negative: "W", limit: 180) else {
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
        if fields[field: c.valid]?.uppercased() == "DGPS" {
            quality.fix = .dgps
        } else {
            switch fields[field: c.fixMode]?.uppercased() {
            case "2D": quality.fix = .twoD
            case "3D": quality.fix = .threeD
            default: break
            }
        }
        let point = TrackPoint(latitude: lat, longitude: lon, elevation: CSVRecords.number(fields[field: c.height]),
                               time: time, quality: quality)
        points.append(point)

        switch fields[field: c.tag]?.uppercased() {
        case "C", "D":
            markers += 1
            waypoints.append(waypoint(at: point, name: "POI \(markers)"))
        case "V":
            markers += 1
            let name = fields[field: c.vox].map { voice in
                voice.contains(".") ? String(voice) : voice + ".WAV"
            } ?? "POI \(markers)"
            waypoints.append(waypoint(at: point, name: name))
        default:
            break
        }
    }

    private func waypoint(at point: TrackPoint, name: String) -> Waypoint {
        Waypoint(latitude: point.latitude, longitude: point.longitude, elevation: point.elevation, time: point.time,
                 name: name, quality: point.quality)
    }

    /// `YYMMDD` (2000...2099) and `hhmmss`, UTC.
    static func time(date: Substring, time: Substring) -> Date? {
        guard date.count == 6, time.count == 6, let d = CSVRecords.digits(date), let t = CSVRecords.digits(time) else {
            return nil
        }
        return UTCTime.date(year: 2000 + d / 10_000, month: d / 100 % 100, day: d % 100,
                            hour: t / 10_000, minute: t / 100 % 100, second: Double(t % 100))
    }

    /// Decimal degrees followed by the hemisphere letter, e.g. `50.000000N`.
    static func coordinate(_ field: Substring, positive: Character, negative: Character,
                           limit: Double) -> CSVValues.CoordinateValue? {
        guard let hemisphere = field.last?.uppercased().first,
              let magnitude = CSVRecords.number(CSVRecords.trimmed(field.dropLast())), magnitude >= 0 else { return nil }
        return CSVValues.coordinate(magnitude: magnitude, hemisphere: hemisphere, positive: positive,
                                    negative: negative, limit: limit)
    }
}
