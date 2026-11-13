import Foundation

/// Garmin Training Center XML (TCX v2, spec `tcx-import`), read according to the public schemas
/// `TrainingCenterDatabasev2.xsd` and `ActivityExtensionv2.xsd`.
///
/// Every `Activity` becomes an unnamed track, every `Course` a track named after it; each `Track`
/// element is a segment. `CoursePoint`s become waypoints. Sport data is ignored.
public struct TCXFileFormat: FileFormat {
    public init() {}

    public var id: FileFormatID { .tcx }
    public var displayName: String { LocalizedStrings.string("format.tcx") }
    public var fileExtensions: [String] { ["tcx", "xml"] }

    /// The first element of the document is `TrainingCenterDatabase` (with or without prefix).
    public func matches(prefix: Data) -> Bool {
        XMLSniffer.rootElementLocalName(in: prefix) == "TrainingCenterDatabase"
    }

    public func read(_ inputs: [FileInput]) throws -> ImportResult {
        var recording = Recording()
        var warnings: [ImportWarning] = []
        for input in inputs {
            let handler = TCXParserHandler(fileName: input.name)
            let parser = XMLParser(data: input.data)
            parser.shouldProcessNamespaces = true
            parser.shouldResolveExternalEntities = false
            parser.delegate = handler
            let success = parser.parse()
            if handler.cancelled {
                throw CancellationError()
            }
            if !success || !handler.sawRoot {
                let line = parser.lineNumber > 0 ? parser.lineNumber : nil
                throw GPSLoggerError(.malformed(line: line), fileName: input.name,
                                     detail: handler.rootError ?? parser.parserError?.localizedDescription ?? "")
            }
            recording.tracks += handler.tracks
            recording.waypoints += handler.waypoints
            warnings += handler.warnings.warnings
        }
        return ImportResult(recording: recording, warnings: warnings)
    }
}

/// Builds the model while `XMLParser` streams through a TCX document. Used only inside one `read` call.
private final class TCXParserHandler: NSObject, XMLParserDelegate {
    var tracks: [Track] = []
    var waypoints: [Waypoint] = []
    var warnings: WarningCollector
    var cancelled = false
    var sawRoot = false
    var rootError: String?

    private var cancellation = CancellationCheck()
    /// Local names of the open elements.
    private var stack: [String] = []
    /// Depth inside an ignored subtree, 0 when not ignoring.
    private var ignoreDepth = 0
    private var text = ""

    private var track: Track?
    private var segment: [TrackPoint]?
    /// The `Trackpoint` or `CoursePoint` being read.
    private var point: PointBuilder?

    private struct PointBuilder {
        var line: Int
        var latitude: String?
        var longitude: String?
        var altitude: String?
        var time: String?
        var speed: String?
        var name: String?
        var notes: String?
    }

    /// Subtrees that are not evaluated (spec "Nicht ausgewertete Inhalte").
    private static let ignored: Set<String> = ["Workouts", "MultiSportSession", "Folders", "Author", "Creator"]
    /// Leaf elements whose text is collected.
    private static let textElements: Set<String> = [
        "LatitudeDegrees", "LongitudeDegrees", "AltitudeMeters", "Time", "Speed", "Name", "Notes",
    ]

    init(fileName: String) {
        warnings = WarningCollector(fileName: fileName)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        do {
            try cancellation.tick()
        } catch {
            cancelled = true
            parser.abortParsing()
            return
        }
        let name = XMLSniffer.localName(elementName)
        if stack.isEmpty {
            sawRoot = name == "TrainingCenterDatabase"
            if !sawRoot {
                rootError = "root element is <\(name)>, not <TrainingCenterDatabase>"
                parser.abortParsing()
                return
            }
        }
        stack.append(name)
        text = ""
        if ignoreDepth > 0 {
            ignoreDepth += 1
            return
        }
        switch name {
        case _ where Self.ignored.contains(name):
            ignoreDepth = 1
        case "Activity", "Course":
            track = Track()
        case "Track" where track != nil:
            segment = []
        case "Trackpoint" where segment != nil, "CoursePoint" where track != nil:
            point = PointBuilder(line: parser.lineNumber)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if ignoreDepth == 0, let current = stack.last, Self.textElements.contains(current) {
            text += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let name = stack.popLast() ?? elementName
        if ignoreDepth > 0 {
            ignoreDepth -= 1
            return
        }
        let parent = stack.last
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""

        if point != nil {
            switch (name, parent) {
            case ("LatitudeDegrees", "Position"): point?.latitude = value
            case ("LongitudeDegrees", "Position"): point?.longitude = value
            case ("AltitudeMeters", "Trackpoint"), ("AltitudeMeters", "CoursePoint"): point?.altitude = value
            case ("Time", "Trackpoint"), ("Time", "CoursePoint"): point?.time = value
            case ("Speed", "TPX"): point?.speed = value
            case ("Name", "CoursePoint"): point?.name = value
            case ("Notes", "CoursePoint"): point?.notes = value
            case ("Trackpoint", _): finishTrackpoint()
            case ("CoursePoint", _): finishCoursePoint()
            default: break
            }
            return
        }

        switch name {
        case "Name" where parent == "Course":
            track?.name = value.isEmpty ? nil : value
        case "Track":
            if let segment, !segment.isEmpty { track?.segments.append(TrackSegment(points: segment)) }
            segment = nil
        case "Activity", "Course":
            if let track, track.pointCount > 0 { tracks.append(track) }
            track = nil
        default:
            break
        }
    }

    /// Position, altitude and speed of the current point, or `nil` (with a warning) if unusable.
    /// Returns `.some(nil)` for a point without position, which is skipped silently.
    private func position(of p: PointBuilder) -> (latitude: Double, longitude: Double, altitude: Double?)?? {
        guard p.latitude != nil || p.longitude != nil else { return .some(nil) }
        guard let latitude = p.latitude.flatMap(Double.init), let longitude = p.longitude.flatMap(Double.init) else {
            warnings.add(.malformedRecord, line: p.line)
            return nil
        }
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            warnings.add(.invalidCoordinate, line: p.line)
            return nil
        }
        var altitude: Double?
        if let text = p.altitude, !text.isEmpty {
            guard let value = Double(text) else {
                warnings.add(.malformedRecord, line: p.line)
                return nil
            }
            altitude = value
        }
        return .some((latitude, longitude, altitude))
    }

    private func time(of p: PointBuilder) -> Date? {
        let time = p.time.flatMap { ISO8601.date($0) }
        if time == nil { warnings.add(.missingDate, line: p.line) }
        return time
    }

    private func finishTrackpoint() {
        defer { point = nil }
        guard let p = point, let result = position(of: p), let position = result else { return }
        var quality = PositionQuality()
        if let speed = p.speed, !speed.isEmpty {
            guard let value = Double(speed) else {
                warnings.add(.malformedRecord, line: p.line)
                return
            }
            quality.speed = value
        }
        segment?.append(TrackPoint(latitude: position.latitude, longitude: position.longitude,
                                   elevation: position.altitude, time: time(of: p), quality: quality))
    }

    private func finishCoursePoint() {
        defer { point = nil }
        guard let p = point, let result = position(of: p), let position = result else { return }
        let time = p.time.flatMap { ISO8601.date($0) }
        waypoints.append(Waypoint(latitude: position.latitude, longitude: position.longitude, elevation: position.altitude,
                                  time: time, name: p.name.flatMap { $0.isEmpty ? nil : $0 },
                                  comment: p.notes.flatMap { $0.isEmpty ? nil : $0 }))
    }
}
