import Foundation

/// KML (Keyhole Markup Language) and KMZ archives (spec `kml-import`), read according to OGC KML 2.2,
/// Google's `gx` extensions and, for KMZ, PKWARE's ZIP specification.
///
/// Every `Placemark` with `LineString`s or `gx:Track`s becomes a track with one segment per path;
/// every `Point` becomes a waypoint. Elements are matched by local name, so all KML namespaces and
/// files without namespace are read alike.
public struct KMLFileFormat: FileFormat {
    public init() {}

    public var id: FileFormatID { .kml }
    public var displayName: String { LocalizedStrings.string("format.kml") }
    public var fileExtensions: [String] { ["kml", "kmz"] }

    /// A document whose first element is `kml`, or a ZIP archive whose first entry ends in `.kml`.
    public func matches(prefix: Data) -> Bool {
        if KMZArchive.isZIP(prefix) {
            return KMZArchive.firstEntryName(in: prefix)?.lowercased().hasSuffix(".kml") ?? false
        }
        return XMLSniffer.rootElementLocalName(in: prefix) == "kml"
    }

    public func read(_ inputs: [FileInput]) throws -> ImportResult {
        var recording = Recording()
        var warnings: [ImportWarning] = []
        for input in inputs {
            var collector = WarningCollector(fileName: input.name)
            let document = KMZArchive.isZIP(input.data)
                ? try KMZArchive.document(in: input.data, fileName: input.name, warnings: &collector)
                : input.data
            let root = try Self.parse(document, fileName: input.name, warnings: &collector)
            var evaluation = KMLEvaluation(fileName: input.name, warnings: collector)
            try evaluation.evaluate(root)
            recording.tracks += evaluation.tracks
            recording.waypoints += evaluation.waypoints
            warnings += evaluation.warnings.warnings
        }
        return ImportResult(recording: recording, warnings: warnings)
    }

    private static func parse(_ data: Data, fileName: String, warnings: inout WarningCollector) throws -> KMLContainer {
        let handler = KMLParserHandler(warnings: warnings)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = handler
        let success = parser.parse()
        if handler.cancelled {
            throw CancellationError()
        }
        guard success, let root = handler.root else {
            let line = parser.lineNumber > 0 ? parser.lineNumber : nil
            throw GPSLoggerError(.malformed(line: line), fileName: fileName,
                                 detail: handler.rootError ?? parser.parserError?.localizedDescription ?? "")
        }
        warnings = handler.warnings
        return root
    }
}

// MARK: - Document tree

/// A `kml`, `Document` or `Folder` element with its own name and its children in file order.
struct KMLContainer {
    var name: String?
    var children: [KMLItem] = []
}

enum KMLItem {
    case container(KMLContainer)
    case placemark(KMLPlacemark)
}

struct KMLPlacemark {
    var name: String?
    var description: String?
    /// Text of `TimeStamp/when`.
    var time: String?
    var paths: [KMLPath] = []
    var points: [KMLPosition] = []
}

/// A `LineString` or `gx:Track`: the points of one segment.
struct KMLPath {
    var isTrack: Bool
    var points: [TrackPoint]
    /// `gx:coord`s without a usable `when`; counted only if the track has times at all.
    var missingDates = 0
    var line: Int
}

struct KMLPosition {
    var latitude: Double
    var longitude: Double
    var elevation: Double?
}

// MARK: - Parser

/// Builds the document tree while `XMLParser` streams through a KML document (design D4).
/// Used only inside one `read` call.
private final class KMLParserHandler: NSObject, XMLParserDelegate {
    var root: KMLContainer?
    var warnings: WarningCollector
    var cancelled = false
    var rootError: String?

    private var cancellation = CancellationCheck()
    private var stack: [String] = []
    private var ignoreDepth = 0
    private var text = ""

    private var containers: [KMLContainer] = []
    private var placemark: KMLPlacemark?
    private var geometry: Geometry?
    private var multiTrackAltitudeMode: String?

    /// The `LineString`, `Point` or `gx:Track` being read.
    private struct Geometry {
        enum Kind { case lineString, point, track }
        var kind: Kind
        var altitudeMode: String?
        var coordinates: [KMLPosition] = []
        var times: [String] = []
        var line: Int
    }

    /// Subtrees that are not evaluated (spec "Unbekannte Inhalte").
    private static let ignored: Set<String> = [
        "Style", "StyleMap", "ExtendedData", "Schema", "Region", "LookAt", "Camera", "Tour", "NetworkLink",
        "Update", "Polygon", "LinearRing", "Model", "GroundOverlay", "ScreenOverlay", "PhotoOverlay", "TimeSpan",
        "Metadata", "NetworkLinkControl",
    ]
    private static let textElements: Set<String> = ["name", "description", "when", "coord", "coordinates", "altitudeMode"]

    init(warnings: WarningCollector) {
        self.warnings = warnings
    }

    private func tick(_ parser: XMLParser) -> Bool {
        do {
            try cancellation.tick()
            return true
        } catch {
            cancelled = true
            parser.abortParsing()
            return false
        }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        guard tick(parser) else { return }
        let name = XMLSniffer.localName(elementName)
        if stack.isEmpty {
            guard name == "kml" else {
                rootError = "root element is <\(name)>, not <kml>"
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
        case "kml", "Document", "Folder":
            containers.append(KMLContainer())
        case "Placemark":
            placemark = KMLPlacemark()
        case "MultiTrack" where placemark != nil:
            multiTrackAltitudeMode = nil
        case "LineString" where placemark != nil:
            geometry = Geometry(kind: .lineString, line: parser.lineNumber)
        case "Point" where placemark != nil:
            geometry = Geometry(kind: .point, line: parser.lineNumber)
        case "Track" where placemark != nil:
            geometry = Geometry(kind: .track, line: parser.lineNumber)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        collect(string, parser)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        collect(String(decoding: CDATABlock, as: UTF8.self), parser)
    }

    private func collect(_ string: String, _ parser: XMLParser) {
        guard ignoreDepth == 0, let current = stack.last, Self.textElements.contains(current) else { return }
        guard tick(parser) else { return }
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        guard !cancelled else { return }
        let name = stack.popLast() ?? elementName
        if ignoreDepth > 0 {
            ignoreDepth -= 1
            return
        }
        let parent = stack.last
        let value = text
        text = ""

        switch (name, parent) {
        case ("name", "Placemark"):
            placemark?.name = Self.trimmed(value)
        case ("name", "Document"), ("name", "Folder"), ("name", "kml"):
            if !containers.isEmpty { containers[containers.count - 1].name = Self.trimmed(value) }
        case ("description", "Placemark"):
            placemark?.description = Self.trimmed(value)
        case ("when", "TimeStamp") where stack.dropLast().last == "Placemark":
            placemark?.time = Self.trimmed(value)
        case ("when", "Track"):
            geometry?.times.append(value)
        case ("coord", "Track"):
            if geometry != nil, let position = parseGXCoord(value, line: parser.lineNumber) {
                geometry?.coordinates.append(position)
            }
        case ("coordinates", "LineString"), ("coordinates", "Point"):
            if geometry != nil, !parseCoordinates(value, line: parser.lineNumber, parser) { return }
        case ("altitudeMode", "LineString"), ("altitudeMode", "Point"), ("altitudeMode", "Track"):
            geometry?.altitudeMode = Self.trimmed(value)
        case ("altitudeMode", "MultiTrack"):
            multiTrackAltitudeMode = Self.trimmed(value)
        case ("LineString", _), ("Point", _), ("Track", _):
            finishGeometry()
        case ("MultiTrack", _):
            multiTrackAltitudeMode = nil
        case ("Placemark", _):
            if let placemark, !containers.isEmpty { containers[containers.count - 1].children.append(.placemark(placemark)) }
            placemark = nil
        case ("Document", _), ("Folder", _):
            if let container = containers.popLast(), !containers.isEmpty {
                containers[containers.count - 1].children.append(.container(container))
            }
        case ("kml", _):
            root = containers.popLast()
        default:
            break
        }
    }

    private static func trimmed(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    // MARK: Coordinates

    /// Reads `lon,lat[,alt]` tuples separated by white space; white space after (or before) a comma
    /// is tolerated. Returns `false` when cancelled.
    private func parseCoordinates(_ text: String, line: Int, _ parser: XMLParser) -> Bool {
        var tuple: [UInt8] = []
        var sawSpace = false
        let comma = UInt8(ascii: ",")
        for byte in text.utf8 {
            if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
                if !tuple.isEmpty { sawSpace = true }
                continue
            }
            if sawSpace {
                sawSpace = false
                if byte != comma, tuple.last != comma {
                    finishTuple(tuple, line: line)
                    tuple.removeAll(keepingCapacity: true)
                    guard tick(parser) else { return false }
                }
            }
            tuple.append(byte)
        }
        if !tuple.isEmpty { finishTuple(tuple, line: line) }
        return true
    }

    private func finishTuple(_ tuple: [UInt8], line: Int) {
        let parts = tuple.split(separator: UInt8(ascii: ","), omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        if let position = position(from: parts, line: line) {
            geometry?.coordinates.append(position)
        }
    }

    /// `gx:coord`: longitude, latitude and optional altitude separated by white space.
    private func parseGXCoord(_ text: String, line: Int) -> KMLPosition? {
        let parts = text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }).map(String.init)
        return position(from: parts, line: line)
    }

    private func position(from parts: [String], line: Int) -> KMLPosition? {
        let parts = parts.count == 3 && parts[2].isEmpty ? Array(parts.prefix(2)) : parts
        guard parts.count == 2 || parts.count == 3,
              let longitude = Double(parts[0]), let latitude = Double(parts[1]) else {
            warnings.add(.malformedRecord, line: line)
            return nil
        }
        var elevation: Double?
        if parts.count == 3 {
            guard let value = Double(parts[2]) else {
                warnings.add(.malformedRecord, line: line)
                return nil
            }
            elevation = value
        }
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            warnings.add(.invalidCoordinate, line: line)
            return nil
        }
        return KMLPosition(latitude: latitude, longitude: longitude, elevation: elevation)
    }

    // MARK: Geometries

    private func finishGeometry() {
        guard let geometry else { return }
        self.geometry = nil
        let mode = geometry.altitudeMode ?? (geometry.kind == .track ? multiTrackAltitudeMode : nil)
        let positions = Self.applyingAltitudeRule(geometry.coordinates, altitudeMode: mode)
        switch geometry.kind {
        case .point:
            placemark?.points += positions
        case .lineString:
            placemark?.paths.append(KMLPath(isTrack: false, points: positions.map {
                TrackPoint(latitude: $0.latitude, longitude: $0.longitude, elevation: $0.elevation)
            }, line: geometry.line))
        case .track:
            var missing = 0
            let points = positions.enumerated().map { index, p in
                let time = index < geometry.times.count ? ISO8601.date(geometry.times[index]) : nil
                if time == nil { missing += 1 }
                return TrackPoint(latitude: p.latitude, longitude: p.longitude, elevation: p.elevation, time: time)
            }
            placemark?.paths.append(KMLPath(isTrack: true, points: points, missingDates: missing, line: geometry.line))
        }
    }

    /// Spec "Höhe": kept for `absolute` or no mode, dropped for any explicit ground or sea floor
    /// reference and when all altitudes of the geometry are 0.
    static func applyingAltitudeRule(_ positions: [KMLPosition], altitudeMode: String?) -> [KMLPosition] {
        let keep = (altitudeMode == nil || altitudeMode == "absolute")
            && positions.contains { ($0.elevation ?? 0) != 0 }
        guard !keep else { return positions }
        return positions.map { KMLPosition(latitude: $0.latitude, longitude: $0.longitude, elevation: nil) }
    }
}

// MARK: - Evaluation

/// Turns the document tree into tracks and waypoints (design D4, D5).
private struct KMLEvaluation {
    let fileName: String
    var warnings: WarningCollector
    var tracks: [Track] = []
    var waypoints: [Waypoint] = []
    private var cancellation = CancellationCheck(interval: 256)
    private var sawTrackWithoutTimes = false

    /// gpsbabel writes coordinates with 6 decimals.
    static let pointsTolerance = 0.000_001 + 1e-9
    /// gpsbabel's fixed name of track placemarks.
    static let placeholderName = "Path"

    init(fileName: String, warnings: WarningCollector) {
        self.fileName = fileName
        self.warnings = warnings
    }

    mutating func evaluate(_ root: KMLContainer) throws {
        var root = root
        Self.applyPointsRule(&root)
        try visit(root, inheritedName: nil)
        if sawTrackWithoutTimes {
            warnings.add(.missingTimes, line: nil)
        }
    }

    private mutating func visit(_ container: KMLContainer, inheritedName: String?) throws {
        let name = container.name ?? inheritedName
        for child in container.children {
            switch child {
            case .container(let inner):
                try visit(inner, inheritedName: name)
            case .placemark(let placemark):
                try cancellation.tick()
                add(placemark, containerName: name)
            }
        }
    }

    private mutating func add(_ placemark: KMLPlacemark, containerName: String?) {
        let segments = placemark.paths.filter { !$0.points.isEmpty }
        if !segments.isEmpty {
            let hasTimes = segments.contains { path in path.points.contains { $0.time != nil } }
            if hasTimes {
                for path in segments where path.missingDates > 0 {
                    warnings.add(.missingDate, line: path.line, count: path.missingDates)
                }
            } else {
                sawTrackWithoutTimes = true
            }
            var trackName = placemark.name
            if trackName == nil || trackName == Self.placeholderName {
                trackName = containerName ?? baseName(ofFile: fileName)
            }
            tracks.append(Track(name: trackName, segments: segments.map { TrackSegment(points: $0.points) }))
        }
        let time = placemark.time.flatMap { ISO8601.date($0) }
        for point in placemark.points {
            waypoints.append(Waypoint(latitude: point.latitude, longitude: point.longitude, elevation: point.elevation,
                                      time: time, name: placemark.name, comment: placemark.description))
        }
    }

    /// Design D5: a `Folder` "Points" next to exactly one path placemark gives that track its times
    /// when it matches point by point; it is then removed. Applied to every container.
    static func applyPointsRule(_ container: inout KMLContainer) {
        if let pointsIndex = container.children.firstIndex(where: {
            if case .container(let c) = $0 { return c.name == "Points" }
            return false
        }), case .container(let points) = container.children[pointsIndex] {
            let pathPlacemarks = container.children.indices.filter {
                if case .placemark(let p) = container.children[$0] { return !p.paths.isEmpty }
                return false
            }
            if pathPlacemarks.count == 1, case .placemark(var track) = container.children[pathPlacemarks[0]],
               let times = matchingTimes(points, track: track) {
                var index = 0
                for p in track.paths.indices {
                    for q in track.paths[p].points.indices {
                        track.paths[p].points[q].time = times[index]
                        index += 1
                    }
                }
                container.children[pathPlacemarks[0]] = .placemark(track)
                container.children.remove(at: pointsIndex)
            }
        }
        for index in container.children.indices {
            if case .container(var inner) = container.children[index] {
                applyPointsRule(&inner)
                container.children[index] = .container(inner)
            }
        }
    }

    /// The times of the "Points" folder if it matches the track's points exactly, else `nil`.
    private static func matchingTimes(_ folder: KMLContainer, track: KMLPlacemark) -> [Date]? {
        guard track.paths.allSatisfy({ !$0.isTrack }) else { return nil }
        let trackPoints = track.paths.flatMap(\.points)
        guard folder.children.count == trackPoints.count, !trackPoints.isEmpty else { return nil }
        var times: [Date] = []
        times.reserveCapacity(trackPoints.count)
        for (child, trackPoint) in zip(folder.children, trackPoints) {
            guard case .placemark(let placemark) = child, placemark.paths.isEmpty, placemark.points.count == 1,
                  let time = placemark.time.flatMap({ ISO8601.date($0) }) else { return nil }
            let point = placemark.points[0]
            guard abs(point.latitude - trackPoint.latitude) <= pointsTolerance,
                  abs(point.longitude - trackPoint.longitude) <= pointsTolerance else { return nil }
            times.append(time)
        }
        return times
    }
}
