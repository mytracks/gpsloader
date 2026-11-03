import Foundation

/// Writes recordings as GPX 1.1 (spec `gpx-export`).
///
/// - Element order follows the GPX 1.1 XSD.
/// - Times are UTC (`Z`), milliseconds only when not zero.
/// - Numbers never depend on the locale.
/// - The same input and creation time always produce byte-identical output.
/// - Quality values (`fix`, `sat`, `hdop`, `vdop`, `pdop`) in schema order; speed and course are not
///   part of GPX 1.1 without extensions and are therefore not written.
/// - No extensions.
public struct GPXWriter: Sendable {
    public static let namespace = "http://www.topografix.com/GPX/1/1"
    public static let schemaLocation = "http://www.topografix.com/GPX/1/1/gpx.xsd"

    /// Value of the `creator` attribute, e.g. "MyApp 1.0".
    public var creator: String

    public init(creator: String) {
        self.creator = creator
    }

    /// The GPX document as UTF-8 data.
    public func data(for recording: Recording, createdAt: Date) -> Data {
        Data(document(for: recording, createdAt: createdAt).utf8)
    }

    /// Writes the document atomically. On failure nothing is left at `url` and an existing file stays unchanged.
    /// - Throws: `GPSLoggerError` of kind `.writeFailed`.
    public func write(_ recording: Recording, to url: URL, createdAt: Date = Date()) throws {
        do {
            try data(for: recording, createdAt: createdAt).write(to: url, options: .atomic)
        } catch {
            throw GPSLoggerError(.writeFailed, fileName: url.lastPathComponent,
                                 detail: "\(url.path): \(error.localizedDescription)")
        }
    }

    // MARK: - Document

    public func document(for recording: Recording, createdAt: Date) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="\(Self.escape(creator))" xmlns="\(Self.namespace)" \
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" \
        xsi:schemaLocation="\(Self.namespace) \(Self.schemaLocation)">
          <metadata>
            <time>\(GPXText.time(createdAt))</time>
          </metadata>

        """

        for waypoint in recording.waypoints {
            xml += "  <wpt \(Self.coordinates(waypoint.latitude, waypoint.longitude))>\n"
            if let elevation = waypoint.elevation {
                xml += "    <ele>\(GPXText.elevation(elevation))</ele>\n"
            }
            if let time = waypoint.time {
                xml += "    <time>\(GPXText.time(time))</time>\n"
            }
            if let name = waypoint.name {
                xml += "    <name>\(Self.escape(name))</name>\n"
            }
            if let comment = waypoint.comment {
                xml += "    <cmt>\(Self.escape(comment))</cmt>\n"
            }
            xml += Self.quality(waypoint.quality, indent: "    ")
            xml += "  </wpt>\n"
        }

        for (index, track) in recording.tracks.enumerated() {
            xml += "  <trk>\n"
            xml += "    <name>\(Self.escape(Self.name(of: track, index: index)))</name>\n"
            for segment in track.segments {
                xml += "    <trkseg>\n"
                for point in segment.points {
                    let attributes = Self.coordinates(point.latitude, point.longitude)
                    if point.elevation == nil && point.time == nil && point.quality.isEmpty {
                        xml += "      <trkpt \(attributes)/>\n"
                        continue
                    }
                    xml += "      <trkpt \(attributes)>\n"
                    if let elevation = point.elevation {
                        xml += "        <ele>\(GPXText.elevation(elevation))</ele>\n"
                    }
                    if let time = point.time {
                        xml += "        <time>\(GPXText.time(time))</time>\n"
                    }
                    xml += Self.quality(point.quality, indent: "        ")
                    xml += "      </trkpt>\n"
                }
                xml += "    </trkseg>\n"
            }
            xml += "  </trk>\n"
        }

        xml += "</gpx>\n"
        return xml
    }

    /// Track name; falls back to the UTC start time or "Track n".
    static func name(of track: Track, index: Int) -> String {
        if let name = track.name, !name.isEmpty {
            return name
        }
        if let start = track.segments.lazy.flatMap(\.points).compactMap(\.time).first {
            return GPXText.displayTime(start)
        }
        return "Track \(index + 1)"
    }

    /// `fix`, `sat`, `hdop`, `vdop`, `pdop` in the order of the GPX 1.1 schema.
    private static func quality(_ quality: PositionQuality, indent: String) -> String {
        guard !quality.isEmpty else { return "" }
        var xml = ""
        if let fix = quality.fix {
            xml += "\(indent)<fix>\(fix.rawValue)</fix>\n"
        }
        if let satellites = quality.satellites, satellites >= 0 {
            xml += "\(indent)<sat>\(satellites)</sat>\n"
        }
        for (name, value) in [("hdop", quality.hdop), ("vdop", quality.vdop), ("pdop", quality.pdop)] {
            if let value {
                xml += "\(indent)<\(name)>\(GPXText.fixed(value, decimals: 2))</\(name)>\n"
            }
        }
        return xml
    }

    private static func coordinates(_ latitude: Double, _ longitude: Double) -> String {
        "lat=\"\(GPXText.coordinate(latitude))\" lon=\"\(GPXText.coordinate(longitude))\""
    }

    /// Escapes text for XML content and attributes and drops characters XML 1.0 does not allow.
    static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            case "\t", "\n", "\r": result.unicodeScalars.append(scalar)
            default:
                if scalar.value >= 0x20 && !(0xFFFE...0xFFFF).contains(scalar.value) {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }
}

/// Locale independent formatting for GPX values.
enum GPXText {
    /// Up to 7 decimals, no trailing zeros, "." as decimal separator.
    static func coordinate(_ value: Double) -> String {
        fixed(value, decimals: 7)
    }

    /// Up to 2 decimals, no trailing zeros.
    static func elevation(_ value: Double) -> String {
        fixed(value, decimals: 2)
    }

    static func fixed(_ value: Double, decimals: Int) -> String {
        // String(format:) without a locale always uses "." and no grouping.
        var text = String(format: "%.\(decimals)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        if text == "-0" { text = "0" }
        return text
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// ISO 8601 in UTC with "Z"; milliseconds only when not zero.
    static func time(_ date: Date) -> String {
        let totalMilliseconds = (date.timeIntervalSince1970 * 1000).rounded()
        let seconds = (totalMilliseconds / 1000).rounded(.down)
        let milliseconds = Int(totalMilliseconds - seconds * 1000)
        let components = utcCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                                    from: Date(timeIntervalSince1970: seconds))
        var text = String(format: "%04d-%02d-%02dT%02d:%02d:%02d",
                          components.year ?? 0, components.month ?? 0, components.day ?? 0,
                          components.hour ?? 0, components.minute ?? 0, components.second ?? 0)
        if milliseconds != 0 {
            text += String(format: ".%03d", milliseconds)
        }
        return text + "Z"
    }

    /// Short UTC time for generated track names, e.g. "2026-11-02 14:30 UTC".
    static func displayTime(_ date: Date) -> String {
        let components = utcCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02d %02d:%02d UTC",
                      components.year ?? 0, components.month ?? 0, components.day ?? 0,
                      components.hour ?? 0, components.minute ?? 0)
    }
}
