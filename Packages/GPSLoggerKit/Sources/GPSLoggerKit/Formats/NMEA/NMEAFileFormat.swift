import Foundation

/// NMEA 0183 log files (spec `nmea-import`).
///
/// All files of one read operation form one track; every file starts a new segment, and so does
/// a time that lies before the previous one.
public struct NMEAFileFormat: FileFormat {
    public init() {}

    public var id: FileFormatID { .nmea }
    public var displayName: String { LocalizedStrings.string("format.nmea") }
    public var fileExtensions: [String] { ["nmea", "nma", "txt", "log", "gps"] }

    /// At least three syntactically valid sentences among the lines of the prefix.
    public func matches(prefix: Data) -> Bool {
        var valid = 0
        for line in Self.lines(of: prefix) {
            if case .valid = NMEASentence.validate(line.text) {
                valid += 1
                if valid >= 3 { return true }
            }
        }
        return false
    }

    public func read(_ inputs: [FileInput]) throws -> ImportResult {
        var segments: [TrackSegment] = []
        var waypoints: [Waypoint] = []
        var warnings: [ImportWarning] = []
        for input in inputs {
            var reader = NMEAFileReader(fileName: input.name)
            try reader.read(input.data)
            segments += reader.segments.filter { !$0.points.isEmpty }
            waypoints += reader.waypoints
            warnings += reader.warnings.warnings
        }
        let tracks = segments.isEmpty ? [] : [Track(segments: segments)]
        return ImportResult(recording: Recording(tracks: tracks, waypoints: waypoints), warnings: warnings)
    }

    /// Splits data into lines (LF, CR or CRLF). Bytes are decoded as UTF-8 with replacement.
    static func lines(of data: Data) -> [(number: Int, text: Substring)] {
        var result: [(Int, Substring)] = []
        forEachLine(in: data) { number, text in
            result.append((number, text))
            return true
        }
        return result
    }

    /// Calls `body` for every line that starts with `$` (other lines are skipped without decoding).
    /// `body` returns `false` to stop.
    static func forEachLine(in data: Data, _ body: (Int, Substring) throws -> Bool) rethrows {
        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            let bytes = buffer.bindMemory(to: UInt8.self)
            var lineNumber = 0
            var start = 0
            var i = 0
            let count = bytes.count
            while start < count {
                i = start
                while i < count, bytes[i] != 0x0A, bytes[i] != 0x0D { i += 1 }
                lineNumber += 1
                if i > start, bytes[start] == 0x24 {  // "$"
                    let text = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<i]), as: UTF8.self)
                    if try !body(lineNumber, Substring(text)) { return }
                }
                // Skip the terminator; CRLF counts as one line break.
                if i < count, bytes[i] == 0x0D, i + 1 < count, bytes[i + 1] == 0x0A {
                    start = i + 2
                } else {
                    start = i + 1
                }
            }
        }
    }
}

/// Reads one NMEA file: collects sentences per epoch (same UTC time) and resolves dates.
struct NMEAFileReader {
    private(set) var segments: [TrackSegment] = []
    private(set) var waypoints: [Waypoint] = []
    var warnings: WarningCollector

    /// Values gathered for the current epoch.
    private struct Epoch {
        var timeOfDay: Int?
        var line: Int
        var date: Int?
        var rmcPosition: (Double, Double)?
        var ggaPosition: (Double, Double)?
        var gllPosition: (Double, Double)?
        var elevation: Double?
        var speed: Double?
        var course: Double?
        var vtgSpeed: Double?
        var vtgCourse: Double?
        var satellites: Int?
        var ggaHDOP: Double?
        var gsaHDOP: Double?
        var vdop: Double?
        var pdop: Double?
        var gsaFix: FixType?
        var dgps = false

        var position: (Double, Double)? { rmcPosition ?? ggaPosition ?? gllPosition }
    }

    private var epoch: Epoch?
    /// Points of this file in order, and their time of day (needed to date points read before the first date).
    private var points: [TrackPoint] = []
    private var timesOfDay: [Int?] = []
    /// Days since 1970 of the current epoch, once known.
    private var currentDate: Int?
    private var lastTimeOfDay: Int?
    /// Index of the first point that still waits for a date.
    private var firstUndated: Int?

    init(fileName: String) {
        warnings = WarningCollector(fileName: fileName)
    }

    mutating func read(_ data: Data) throws {
        var cancellation = CancellationCheck()
        try NMEAFileFormat.forEachLine(in: data) { number, line in
            try cancellation.tick()
            switch NMEASentence.validate(line) {
            case .valid(let sentence): handle(sentence, line: number)
            case .ignored: break
            case .checksumMismatch: warnings.add(.checksumMismatch, line: number)
            case .malformed: warnings.add(.malformedRecord, line: number)
            }
            return true
        }
        flushEpoch()
        finish()
    }

    // MARK: Sentences

    private mutating func handle(_ s: NMEASentence, line: Int) {
        switch s.type {
        case "RMC":
            guard s.fields.count >= 9 else { return warnings.add(.malformedRecord, line: line) }
            startEpoch(NMEASentence.timeOfDay(s[0]), line: line)
            let valid = s[1] == "A" && s[11] != "N"
            guard valid else { return }
            if let date = NMEASentence.date(ddmmyy: s[8]) { epoch?.date = date }
            guard let position = position(s[2], s[3], s[4], s[5], line: line) else { return }
            epoch?.rmcPosition = position
            if let knots = NMEASentence.double(s[6]) { epoch?.speed = knots * 1852 / 3600 }
            if let course = NMEASentence.double(s[7]) { epoch?.course = course }
        case "GGA":
            guard s.fields.count >= 9 else { return warnings.add(.malformedRecord, line: line) }
            startEpoch(NMEASentence.timeOfDay(s[0]), line: line)
            guard let quality = NMEASentence.int(s[5]), quality > 0 else { return }
            guard let position = position(s[1], s[2], s[3], s[4], line: line) else { return }
            epoch?.ggaPosition = position
            epoch?.dgps = quality == 2
            if let satellites = NMEASentence.int(s[6]) { epoch?.satellites = satellites }
            if let hdop = NMEASentence.double(s[7]) { epoch?.ggaHDOP = hdop }
            if let altitude = NMEASentence.double(s[8]), s[9].isEmpty || s[9] == "M" { epoch?.elevation = altitude }
        case "GLL":
            guard s.fields.count >= 4 else { return warnings.add(.malformedRecord, line: line) }
            if let time = NMEASentence.timeOfDay(s[4]) { startEpoch(time, line: line) }
            guard s[5] != "V", s[6] != "N" else { return }
            guard let position = position(s[0], s[1], s[2], s[3], line: line) else { return }
            ensureEpoch(line: line)
            epoch?.gllPosition = position
        case "GSA":
            guard epoch != nil else { return }
            switch s[1] {
            case "2": epoch?.gsaFix = .twoD
            case "3": epoch?.gsaFix = .threeD
            case "1": epoch?.gsaFix = FixType.none
            default: break
            }
            if let pdop = NMEASentence.double(s[14]) { epoch?.pdop = pdop }
            if let hdop = NMEASentence.double(s[15]) { epoch?.gsaHDOP = hdop }
            if let vdop = NMEASentence.double(s[16]) { epoch?.vdop = vdop }
        case "VTG":
            guard epoch != nil else { return }
            if s[1] == "T" {
                // NMEA 2.3+: course,T,course,M,knots,N,km/h,K[,mode]
                if s[8] == "N" { return }
                epoch?.vtgCourse = NMEASentence.double(s[0])
                if let kmh = NMEASentence.double(s[6]) {
                    epoch?.vtgSpeed = kmh / 3.6
                } else if let knots = NMEASentence.double(s[4]) {
                    epoch?.vtgSpeed = knots * 1852 / 3600
                }
            } else {
                // Older form without unit letters: course,course(mag),knots,km/h
                epoch?.vtgCourse = NMEASentence.double(s[0])
                if let knots = NMEASentence.double(s[2]) { epoch?.vtgSpeed = knots * 1852 / 3600 }
            }
        case "ZDA":
            guard let time = NMEASentence.timeOfDay(s[0]) else { return }
            startEpoch(time, line: line)
            if let day = NMEASentence.int(s[1]), let month = NMEASentence.int(s[2]), let year = NMEASentence.int(s[3]),
               UTCTime.isValid(year: year, month: month, day: day) {
                epoch?.date = UTCTime.days(year: year, month: month, day: day)
            }
        case "WPL":
            guard let position = position(s[0], s[1], s[2], s[3], line: line) else { return }
            let name = s[4].trimmingCharacters(in: .whitespaces)
            waypoints.append(Waypoint(latitude: position.0, longitude: position.1, name: name.isEmpty ? nil : name))
        default:
            break
        }
    }

    /// Parses a position; counts invalid values as warnings. Missing coordinates give `nil` silently.
    private mutating func position(_ lat: Substring, _ ns: Substring, _ lon: Substring, _ ew: Substring,
                                   line: Int) -> (Double, Double)? {
        let latitude = NMEASentence.coordinate(lat, hemisphere: ns, isLatitude: true)
        let longitude = NMEASentence.coordinate(lon, hemisphere: ew, isLatitude: false)
        switch (latitude, longitude) {
        case (.value(let a), .value(let b)):
            return (a, b)
        case (.missing, .missing):
            return nil
        default:
            warnings.add(.invalidCoordinate, line: line)
            return nil
        }
    }

    // MARK: Epochs

    /// Starts a new epoch when the time differs from the current one. Sentences without a time join the current epoch.
    private mutating func startEpoch(_ time: Int?, line: Int) {
        guard let time else { return ensureEpoch(line: line) }
        if let current = epoch {
            if current.timeOfDay == time { return }
            if current.timeOfDay == nil {
                epoch?.timeOfDay = time
                return
            }
            flushEpoch()
        }
        epoch = Epoch(timeOfDay: time, line: line)
    }

    private mutating func ensureEpoch(line: Int) {
        if epoch == nil { epoch = Epoch(timeOfDay: nil, line: line) }
    }

    /// Turns the collected epoch into a point and advances the date.
    private mutating func flushEpoch() {
        guard let e = epoch else { return }
        epoch = nil

        if let time = e.timeOfDay {
            if let date = e.date {
                setDate(date, at: time)
            } else if currentDate != nil, let last = lastTimeOfDay, time < last - 12 * 3_600_000 {
                currentDate! += 1  // midnight passed without a dated sentence
            }
            lastTimeOfDay = time
        }

        guard let position = e.position else { return }
        var quality = PositionQuality()
        quality.speed = e.speed ?? e.vtgSpeed
        quality.course = e.course ?? e.vtgCourse
        quality.satellites = e.satellites
        quality.hdop = e.ggaHDOP ?? e.gsaHDOP
        quality.vdop = e.vdop
        quality.pdop = e.pdop
        quality.fix = e.dgps ? .dgps : e.gsaFix
        var point = TrackPoint(latitude: position.0, longitude: position.1, elevation: e.elevation, quality: quality)
        if let time = e.timeOfDay, let date = currentDate {
            point.time = Self.date(days: date, timeOfDay: time)
        } else if e.timeOfDay != nil, firstUndated == nil {
            firstUndated = points.count
        }
        points.append(point)
        timesOfDay.append(e.timeOfDay)
    }

    /// Sets the date; the first date also dates all points read before it.
    private mutating func setDate(_ date: Int, at time: Int) {
        if currentDate == nil, let first = firstUndated {
            for index in first..<points.count {
                guard let pointTime = timesOfDay[index] else { continue }
                // Points later in the day than the first dated one must be from the previous day.
                let day = pointTime > time ? date - 1 : date
                points[index].time = Self.date(days: day, timeOfDay: pointTime)
            }
            firstUndated = nil
        }
        currentDate = date
    }

    /// Splits the points into segments (new segment when time goes backwards) and reports undated points.
    /// Without a split the point array is moved into the segment instead of being copied.
    private mutating func finish() {
        var undated = 0
        var boundaries: [Int] = [0]
        var previousTime: Date?
        for index in points.indices {
            let time = points[index].time
            if time == nil, timesOfDay[index] != nil { undated += 1 }
            if let time {
                if let previousTime, time < previousTime, index > boundaries.last! { boundaries.append(index) }
                previousTime = time
            }
        }
        if boundaries.count == 1 {
            segments.append(TrackSegment(points: points))
        } else {
            boundaries.append(points.count)
            for k in 0..<(boundaries.count - 1) {
                segments.append(TrackSegment(points: Array(points[boundaries[k]..<boundaries[k + 1]])))
            }
        }
        points = []
        timesOfDay = []
        if undated > 0 { warnings.add(.missingDate, line: nil, count: undated) }
    }

    static func date(days: Int, timeOfDay: Int) -> Date {
        Date(timeIntervalSince1970: Double(days) * 86_400 + Double(timeOfDay) / 1000)
    }
}
