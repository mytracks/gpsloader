import Foundation
import Testing
@testable import GPSLoggerKit

private let writer = GPXWriter(creator: "gpsloader 0.1.0")
/// 2026-11-02 14:30:05 UTC
private let t0 = Date(timeIntervalSince1970: 1_793_629_805)

private func point(_ lat: Double, _ lon: Double, ele: Double? = 94, time: Date? = t0) -> TrackPoint {
    TrackPoint(latitude: lat, longitude: lon, elevation: ele, time: time)
}

private let sample = Recording(
    tracks: [
        Track(name: "Berg & Tal <1>", segments: [
            TrackSegment(points: [point(51.741158, 8.680967), point(51.7412, 8.681), point(51.7413, 8.6811)]),
            TrackSegment(points: [point(51.75, 8.69), point(51.751, 8.691, ele: nil), point(51.752, 8.692, ele: nil, time: nil)]),
        ]),
    ],
    waypoints: [Waypoint(latitude: 51.7, longitude: 8.6, elevation: 100, time: t0, name: "WPT")]
)

/// Serialized: XMLDocument (libxml2), used for validation in these tests, is not safe to use concurrently.
@Suite("GPXWriter", .serialized)
struct GPXWriterTests {
#if os(macOS) // XMLDocument is not available on iOS
    // MARK: Conformance (task 4.1 / 4.2)

    /// Scenario "Validierung gegen das Schema".
    @Test func outputValidatesAgainstGPX11Schema() throws {
        try GPXSchemaValidator.validate(writer.data(for: sample, createdAt: t0))
    }

    /// Guards against a validator that silently accepts everything.
    @Test func validatorRejectsInvalidGPX() throws {
        let valid = writer.document(for: sample, createdAt: t0)
        // <time> before <ele> violates the element order of wptType.
        let invalid = valid.replacingOccurrences(of: "<ele>94</ele>\n        <time>2026-11-02T14:30:05Z</time>",
                                                 with: "<time>2026-11-02T14:30:05Z</time>\n        <ele>94</ele>")
        #expect(invalid != valid)
        #expect(throws: GPXSchemaValidator.Failure.self) {
            try GPXSchemaValidator.validate(Data(invalid.utf8))
        }
        let unknownElement = valid.replacingOccurrences(of: "<metadata>", with: "<metadata><speed>1</speed>")
        #expect(throws: GPXSchemaValidator.Failure.self) {
            try GPXSchemaValidator.validate(Data(unknownElement.utf8))
        }
    }

    @Test func emptyRecordingIsStillValid() throws {
        try GPXSchemaValidator.validate(writer.data(for: Recording(), createdAt: t0))
    }

    @Test func rootCarriesVersionNamespaceAndCreator() throws {
        let document = try XMLDocument(data: writer.data(for: sample, createdAt: t0))
        let root = try #require(document.rootElement())
        #expect(root.name == "gpx")
        #expect(root.attribute(forName: "version")?.stringValue == "1.1")
        #expect(root.attribute(forName: "creator")?.stringValue == "gpsloader 0.1.0")
        #expect(root.uri == "http://www.topografix.com/GPX/1/1")
    }

#endif

    /// Scenario "Keine Erweiterungen".
    @Test func containsNoExtensions() {
        #expect(!writer.document(for: sample, createdAt: t0).contains("extensions"))
    }

    // MARK: Content

#if os(macOS) // XMLDocument is not available on iOS
    /// Scenario "Track mit Segmenten".
    @Test func trackWithTwoSegments() throws {
        let document = try XMLDocument(data: writer.data(for: sample, createdAt: t0))
        let segments = try document.nodes(forXPath: "/*[local-name()='gpx']/*[local-name()='trk']/*[local-name()='trkseg']")
        #expect(segments.count == 2)
        for segment in segments {
            #expect(segment.children?.count == 3)
        }
    }

#endif

    /// Scenario "Punkt ohne Höhe".
    @Test func pointWithoutElevationHasNoEle() {
        let recording = Recording(tracks: [Track(name: "x", segments: [TrackSegment(points: [point(1, 2, ele: nil)])])])
        let text = writer.document(for: recording, createdAt: t0)
        #expect(!text.contains("<ele>"))
        #expect(text.contains("<time>2026-11-02T14:30:05Z</time>"))
    }

    /// Scenario "Wegpunkt".
    @Test func waypointIsWrittenAsWpt() {
        #expect(writer.document(for: sample, createdAt: t0).contains("<wpt lat=\"51.7\" lon=\"8.6\">"))
        #expect(writer.document(for: sample, createdAt: t0).contains("<name>WPT</name>"))
    }

    @Test func unnamedTrackGetsStartTimeAsName() {
        let recording = Recording(tracks: [Track(segments: [TrackSegment(points: [point(1, 2)])])])
        #expect(writer.document(for: recording, createdAt: t0).contains("<name>2026-11-02 14:30 UTC</name>"))
    }

    // MARK: Times

    /// Scenario "Ganze Sekunden".
    @Test func wholeSecondsHaveNoFraction() {
        #expect(GPXText.time(t0) == "2026-11-02T14:30:05Z")
    }

    /// Scenario "Millisekunden".
    @Test func millisecondsAreWritten() {
        #expect(GPXText.time(t0.addingTimeInterval(0.25)) == "2026-11-02T14:30:05.250Z")
    }

    @Test func timesBefore1970() {
        #expect(GPXText.time(Date(timeIntervalSince1970: -0.5)) == "1969-12-31T23:59:59.500Z")
    }

    // MARK: Numbers

    /// Scenario "Deutsches Gebietsschema": numbers never use the locale.
    @Test func numbersIgnoreLocale() {
        // Proof that a German locale would produce a comma ...
        #expect(String(format: "%.1f", locale: Locale(identifier: "de_DE"), 1.5) == "1,5")
        // ... while the writer does not.
        #expect(GPXText.coordinate(51.7411580) == "51.741158")
        #expect(GPXText.coordinate(-8.0) == "-8")
        #expect(GPXText.coordinate(-0.00000001) == "0")
        #expect(GPXText.coordinate(12345.123456789) == "12345.1234568")
        #expect(GPXText.elevation(94) == "94")
        #expect(GPXText.elevation(1234.567) == "1234.57")
    }

    // MARK: Escaping

#if os(macOS) // XMLDocument is not available on iOS
    /// Scenario "Name mit Sonderzeichen".
    @Test func specialCharactersRoundTrip() throws {
        let document = try XMLDocument(data: writer.data(for: sample, createdAt: t0))
        let names = try document.nodes(forXPath: "//*[local-name()='trk']/*[local-name()='name']")
        #expect(names.first?.stringValue == "Berg & Tal <1>")
    }

#endif

    @Test func invalidControlCharactersAreDropped() {
        #expect(GPXWriter.escape("a\u{01}b\tc") == "ab\tc")
        #expect(GPXWriter.escape("\"'") == "&quot;&apos;")
    }

    // MARK: Determinism and writing (task 4.3)

    /// Scenario "Zweimal exportieren".
    @Test func outputIsDeterministic() {
        #expect(writer.data(for: sample, createdAt: t0) == writer.data(for: sample, createdAt: t0))
    }

    @Test func writesFileAtomically() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("out.gpx")
        try writer.write(sample, to: url, createdAt: t0)
        #expect(try Data(contentsOf: url) == writer.data(for: sample, createdAt: t0))
    }

    /// Scenario "Ziel nicht beschreibbar".
    @Test func readOnlyDirectoryFailsWithoutLeavingAFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = directory.appendingPathComponent("existing.gpx")
        try Data("old".utf8).write(to: existing)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }

        let target = directory.appendingPathComponent("new.gpx")
        #expect {
            try writer.write(sample, to: target, createdAt: t0)
        } throws: { error in
            (error as? GPSLoggerError)?.kind == .writeFailed
        }
        #expect(!FileManager.default.fileExists(atPath: target.path))

        #expect(throws: GPSLoggerError.self) {
            try writer.write(sample, to: existing, createdAt: t0)
        }
        #expect(try Data(contentsOf: existing) == Data("old".utf8))
    }
}
