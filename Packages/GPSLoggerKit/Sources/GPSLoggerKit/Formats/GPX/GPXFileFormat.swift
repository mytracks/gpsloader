import Foundation

/// GPX 1.0 and 1.1 files (spec `gpx-import`): tracks and waypoints; routes and extensions are ignored.
public struct GPXFileFormat: FileFormat {
    public init() {}

    public var id: FileFormatID { .gpx }
    public var displayName: String { LocalizedStrings.string("format.gpx") }
    public var fileExtensions: [String] { ["gpx", "xml"] }

    /// The first element of the document is `gpx` (with or without namespace prefix).
    public func matches(prefix: Data) -> Bool {
        let text = String(decoding: prefix, as: UTF8.self)
        var rest = text[...]
        while let open = rest.firstIndex(of: "<") {
            rest = rest[rest.index(after: open)...]
            guard let next = rest.first else { return false }
            if next == "?" || next == "!" {
                // XML declaration, comment, DOCTYPE: skip to the end of the markup.
                guard let close = rest.firstIndex(of: ">") else { return false }
                rest = rest[rest.index(after: close)...]
                continue
            }
            let name = rest.prefix { !$0.isWhitespace && $0 != ">" && $0 != "/" }
            let localName = name.split(separator: ":").last ?? name
            return localName == "gpx"
        }
        return false
    }

    public func read(_ inputs: [FileInput]) throws -> ImportResult {
        var recording = Recording()
        var warnings: [ImportWarning] = []
        for input in inputs {
            let handler = GPXParserHandler(fileName: input.name)
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

/// Builds the model while `XMLParser` streams through a document. Used only inside one `read` call.
private final class GPXParserHandler: NSObject, XMLParserDelegate {
    var tracks: [Track] = []
    var waypoints: [Waypoint] = []
    var warnings: WarningCollector
    var cancelled = false
    var sawRoot = false
    var rootError: String?

    private var cancellation = CancellationCheck()
    /// Local names of the open elements.
    private var stack: [String] = []
    /// Depth inside an ignored subtree (`extensions`, `rte`), 0 when not ignoring.
    private var ignoreDepth = 0
    private var text = ""

    private var track: Track?
    private var segment: TrackSegment?
    /// The `trkpt` or `wpt` being read; `nil` if its coordinates were invalid.
    private var point: PointBuilder?
    private var pointIsValid = false

    private struct PointBuilder {
        var latitude: Double
        var longitude: Double
        var elevation: Double?
        var time: Date?
        var name: String?
        var comment: String?
        var quality = PositionQuality()
    }

    /// Leaf elements whose text is collected.
    private static let textElements: Set<String> = [
        "ele", "time", "name", "cmt", "sat", "hdop", "vdop", "pdop", "fix", "speed", "course",
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
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if stack.isEmpty {
            sawRoot = name == "gpx"
            if !sawRoot {
                rootError = "root element is <\(name)>, not <gpx>"
                parser.abortParsing()
                return
            }
        }
        stack.append(name)
        if ignoreDepth > 0 {
            ignoreDepth += 1
            return
        }
        switch name {
        case "extensions", "rte":
            ignoreDepth = 1
        case "trk":
            track = Track()
        case "trkseg":
            segment = TrackSegment()
        case "trkpt", "wpt":
            if let latitude = attributes["lat"].flatMap(Double.init),
               let longitude = attributes["lon"].flatMap(Double.init),
               (-90...90).contains(latitude), (-180...180).contains(longitude) {
                point = PointBuilder(latitude: latitude, longitude: longitude)
            } else {
                point = nil
                warnings.add(.invalidCoordinate, line: parser.lineNumber)
            }
        default:
            break
        }
        text = ""
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

        if parent == "trkpt" || parent == "wpt" {
            guard point != nil else { return }
            switch name {
            case "ele": point?.elevation = Double(value)
            case "time": point?.time = ISO8601.date(value)
            case "name": point?.name = value.isEmpty ? nil : value
            case "cmt": point?.comment = value.isEmpty ? nil : value
            case "sat": point?.quality.satellites = Int(value)
            case "hdop": point?.quality.hdop = Double(value)
            case "vdop": point?.quality.vdop = Double(value)
            case "pdop": point?.quality.pdop = Double(value)
            case "speed": point?.quality.speed = Double(value)
            case "course": point?.quality.course = Double(value)
            case "fix":
                switch value {
                case "none": point?.quality.fix = FixType.none
                case "2d": point?.quality.fix = .twoD
                case "3d": point?.quality.fix = .threeD
                case "dgps": point?.quality.fix = .dgps
                default: break
                }
            default: break
            }
            return
        }

        switch name {
        case "name" where parent == "trk":
            track?.name = value.isEmpty ? nil : value
        case "trkpt":
            if let p = point {
                segment?.points.append(TrackPoint(latitude: p.latitude, longitude: p.longitude, elevation: p.elevation,
                                                  time: p.time, quality: p.quality))
            }
            point = nil
        case "wpt":
            if let p = point {
                waypoints.append(Waypoint(latitude: p.latitude, longitude: p.longitude, elevation: p.elevation,
                                          time: p.time, name: p.name, comment: p.comment, quality: p.quality))
            }
            point = nil
        case "trkseg":
            if let segment, !segment.points.isEmpty { track?.segments.append(segment) }
            segment = nil
        case "trk":
            if let track, track.pointCount > 0 { tracks.append(track) }
            track = nil
        default:
            break
        }
    }
}
