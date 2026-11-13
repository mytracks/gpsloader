import Foundation

/// Suunto Ambit SML files as saved by Moveslink/Movescount (spec `suunto-import`). There is no
/// public specification; the layout was derived from sample files (black box, see PROVENANCE.md).
///
/// Every file becomes one track named after the file. Samples with `Latitude`/`Longitude` (radians)
/// are its points; `Pause` events split it into segments.
public struct SuuntoSMLFileFormat: FileFormat {
    public init() {}

    public var id: FileFormatID { .suuntoSML }
    public var displayName: String { LocalizedStrings.string("format.suunto-sml") }
    public var fileExtensions: [String] { ["sml", "xml"] }

    /// The first element of the document is `sml` (with or without prefix).
    public func matches(prefix: Data) -> Bool {
        XMLSniffer.rootElementLocalName(in: prefix) == "sml"
    }

    public func read(_ inputs: [FileInput]) throws -> ImportResult {
        var recording = Recording()
        var warnings: [ImportWarning] = []
        for input in inputs {
            let handler = SuuntoParserHandler(fileName: input.name)
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
            let track = Track(name: baseName(ofFile: input.name), segments: handler.segments)
            if track.pointCount > 0 { recording.tracks.append(track) }
            warnings += handler.warnings.warnings
        }
        return ImportResult(recording: recording, warnings: warnings)
    }

    /// A heading in radians as degrees in 0..<360.
    static func degrees(fromHeading radians: Double) -> Double {
        let degrees = (radians * 180 / .pi).truncatingRemainder(dividingBy: 360)
        return degrees < 0 ? degrees + 360 : degrees
    }
}

/// Builds the track while `XMLParser` streams through an SML document. Used only inside one `read` call.
private final class SuuntoParserHandler: NSObject, XMLParserDelegate {
    var warnings: WarningCollector
    var cancelled = false
    var sawRoot = false
    var rootError: String?

    /// Barometric altitude is used for a point if it is at most this old (spec "Höhe").
    static let barometricAltitudeMaxAge: TimeInterval = 60

    private var cancellation = CancellationCheck()
    private var stack: [String] = []
    private var text = ""
    private var completed: [TrackSegment] = []
    private var segment: [TrackPoint] = []

    /// Direct child values of the `Sample` being read.
    private var sample: [String: String]?
    private var sampleLine = 0
    private var pauseStates: [String] = []
    private var barometric: (altitude: Double, time: Date)?

    init(fileName: String) {
        warnings = WarningCollector(fileName: fileName)
    }

    var segments: [TrackSegment] {
        segment.isEmpty ? completed : completed + [TrackSegment(points: segment)]
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
            sawRoot = name == "sml"
            if !sawRoot {
                rootError = "root element is <\(name)>, not <sml>"
                parser.abortParsing()
                return
            }
        }
        if name == "Sample", stack.last == "Samples" {
            sample = [:]
            sampleLine = parser.lineNumber
            pauseStates = []
        }
        stack.append(name)
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if sample != nil { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let name = stack.popLast() ?? elementName
        let parent = stack.last
        defer { text = "" }
        guard sample != nil else { return }
        if name == "Sample", parent == "Samples" {
            finishSample()
            return
        }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if parent == "Sample" {
            sample?[name] = value
        } else if name == "State", parent == "Pause" {
            pauseStates.append(value)
        }
    }

    private func finishSample() {
        guard let values = sample else { return }
        sample = nil
        let utc = values["UTC"].flatMap { ISO8601.date($0) }

        if values["Latitude"] != nil || values["Longitude"] != nil {
            addPoint(values, time: utc)
        } else if let altitude = values["Altitude"].flatMap(Double.init), let utc {
            barometric = (altitude, utc)
        }

        for state in pauseStates where state.caseInsensitiveCompare("true") == .orderedSame {
            if !segment.isEmpty {
                completed.append(TrackSegment(points: segment))
                segment = []
            }
        }
    }

    private func addPoint(_ values: [String: String], time: Date?) {
        guard let latitude = values["Latitude"].flatMap(Double.init),
              let longitude = values["Longitude"].flatMap(Double.init) else {
            warnings.add(.malformedRecord, line: sampleLine)
            return
        }
        guard abs(latitude) <= .pi / 2, abs(longitude) <= .pi else {
            warnings.add(.invalidCoordinate, line: sampleLine)
            return
        }
        var elevation: Double?
        if let barometric, let time, (0...Self.barometricAltitudeMaxAge).contains(time.timeIntervalSince(barometric.time)) {
            elevation = barometric.altitude
        } else {
            elevation = Self.number(values["GPSAltitude"])
        }
        var quality = PositionQuality()
        quality.speed = Self.number(values["GPSSpeed"])
        quality.course = Self.number(values["GPSHeading"]).map(SuuntoSMLFileFormat.degrees(fromHeading:))
        quality.hdop = Self.number(values["GpsHDOP"])
        quality.satellites = values["NumberOfSatellites"].flatMap { Int($0) }
        if time == nil { warnings.add(.missingDate, line: sampleLine) }
        segment.append(TrackPoint(latitude: latitude * 180 / .pi, longitude: longitude * 180 / .pi,
                                  elevation: elevation, time: time, quality: quality))
    }

    private static func number(_ text: String?) -> Double? {
        guard let text, !text.isEmpty else { return nil }
        return Double(text)
    }
}
