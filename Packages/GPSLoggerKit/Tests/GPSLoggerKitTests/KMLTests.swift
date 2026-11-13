import Foundation
import Testing
@testable import GPSLoggerKit

private let kml22 = "http://www.opengis.net/kml/2.2"
private let gxNamespace = "http://www.google.com/kml/ext/2.2"

private func kml(_ body: String, namespace: String? = kml22) -> String {
    let ns = namespace.map { " xmlns=\"\($0)\"" } ?? ""
    return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<kml\(ns) xmlns:gx=\"\(gxNamespace)\">\n<Document>\(body)</Document></kml>"
}

private func path(_ coordinates: String, name: String? = nil, extra: String = "") -> String {
    "<Placemark>\(name.map { "<name>\($0)</name>" } ?? "")<LineString>\(extra)<coordinates>\(coordinates)</coordinates></LineString></Placemark>"
}

private func read(_ text: String, name: String = "tour.kml") throws -> ImportResult {
    try KMLFileFormat().read([FileInput(name: name, data: Data(text.utf8))])
}

private func points(_ result: ImportResult) -> [TrackPoint] {
    result.recording.tracks.flatMap(\.segments).flatMap(\.points)
}

private func time(_ text: String) -> Date? { ISO8601.date(text) }

/// A gpsbabel-like structure (design D1): track folder with "Path" placemark and "Points" folder.
private func gpsbabelTrack(name: String, segments: [[(Double, Double)]], points: [(Double, Double, String)]) -> String {
    let lines = segments.map { segment in
        "<LineString><tessellate>1</tessellate><coordinates>\n"
            + segment.map { String(format: "%.6f,%.6f,100.00\n", $0.1, $0.0) }.joined() + "</coordinates></LineString>"
    }
    let geometry = lines.count == 1 ? lines[0] : "<MultiGeometry>\(lines.joined())</MultiGeometry>"
    let pointPlacemarks = points.enumerated().map { index, p in
        "<Placemark><name>\(name)-\(index)</name><description><![CDATA[<table><tr><td>x</td></tr></table>]]></description>"
            + "<TimeStamp><when>\(p.2)</when></TimeStamp><styleUrl>#track</styleUrl>"
            + String(format: "<Point><coordinates>%.6f,%.6f,100.00</coordinates></Point></Placemark>", p.1, p.0)
    }.joined()
    return "<Folder><name>Tracks</name><Folder><name>\(name)</name><Placemark><name>Path</name>\(geometry)</Placemark>"
        + "<Folder><name>Points</name>\(pointPlacemarks)</Folder></Folder></Folder>"
}

@Suite("KML – paths and tracks")
struct KMLPathTests {
    /// Scenario "Einfacher Pfad".
    @Test func simplePath() throws {
        let coordinates = (0..<100).map { "8,\(50 + Double($0) / 1000),100" }.joined(separator: " ")
        let result = try read(kml(path(coordinates, name: "Runde")))
        #expect(result.recording.tracks.count == 1)
        #expect(result.recording.tracks[0].segments.map(\.points.count) == [100])
        #expect(points(result).allSatisfy { $0.time == nil })
    }

    /// Scenario "Pfad aus mehreren Teilen".
    @Test func multiGeometry() throws {
        let line = "<LineString><coordinates>8,50 8,50.001 8,50.002</coordinates></LineString>"
        let result = try read(kml("<Placemark><MultiGeometry>\(line)\(line)</MultiGeometry></Placemark>"))
        #expect(result.recording.tracks.map { $0.segments.map(\.points.count) } == [[3, 3]])
    }

    /// Scenario "Google-Mehrfachtrack".
    @Test func multiTrack() throws {
        let track = "<gx:Track><when>2026-05-01T08:00:00Z</when><gx:coord>8 50 0</gx:coord></gx:Track>"
        let result = try read(kml("<Placemark><gx:MultiTrack>\(track)\(track)</gx:MultiTrack></Placemark>"))
        #expect(result.recording.tracks.map { $0.segments.count } == [2])
    }

    /// Scenario "Track mit Zeiten".
    @Test func trackWithTimes() throws {
        let body = "<Placemark><gx:Track><when>2026-05-01T08:00:00Z</when><when>2026-05-01T08:00:10Z</when>"
            + "<gx:coord>8 50 120</gx:coord><gx:coord>8.001 50.001 121</gx:coord></gx:Track></Placemark>"
        let result = try read(kml(body))
        let all = points(result)
        #expect(all.map(\.latitude) == [50, 50.001])
        #expect(all.map(\.longitude) == [8, 8.001])
        #expect(all.map(\.elevation) == [120, 121])
        #expect(all.map(\.time) == [time("2026-05-01T08:00:00Z"), time("2026-05-01T08:00:10Z")])
        #expect(result.warnings.isEmpty)
    }

    /// Scenario "Zu wenige Zeiten"; an unreadable time counts like a missing one.
    @Test func tooFewTimes() throws {
        let body = "<Placemark><gx:Track><when>2026-05-01T08:00:00Z</when><when>gestern</when>"
            + "<gx:coord>8 50 1</gx:coord><gx:coord>8 50.001 1</gx:coord><gx:coord>8 50.002 1</gx:coord></gx:Track></Placemark>"
        let result = try read(kml(body))
        #expect(points(result).map { $0.time != nil } == [true, false, false])
        #expect(result.warnings.map(\.kind) == [.missingDate])
        #expect(result.warnings.first?.count == 2)
    }

    /// A gx:Track without any `when` counts as a track without times, not per point.
    @Test func trackWithoutAnyTime() throws {
        let result = try read(kml("<Placemark><gx:Track><gx:coord>8 50 1</gx:coord><gx:coord>8 50.1 1</gx:coord></gx:Track></Placemark>"))
        #expect(result.warnings.map(\.kind) == [.missingTimes])
    }

    /// Scenario "Export aus myTracks".
    @Test func pathWithoutTimesGivesOneWarning() throws {
        let coordinates = (0..<500).map { "8,\(50 + Double($0) / 10000),100" }.joined(separator: "\n")
        let result = try read(kml(path(coordinates) + path("8,51 8,51.1")))
        #expect(result.recording.trackPointCount == 502)
        #expect(result.warnings == [ImportWarning(kind: .missingTimes, count: 1, fileName: "tour.kml")])
    }

    /// Scenario "Reihenfolge Länge, Breite"; white space after a comma is tolerated.
    @Test func longitudeComesFirst() throws {
        let result = try read(kml(path("8.5,50.25,100   8.5, 50.5 ,101")))
        #expect(points(result).map(\.latitude) == [50.25, 50.5])
        #expect(points(result).map(\.longitude) == [8.5, 8.5])
    }

    /// Scenario "Ungültige Breite" and unreadable tuples.
    @Test func damagedTuplesAreWarnings() throws {
        let result = try read(kml(path("8,50 8,95 abc,50 8 8,50,x 8,50,1,2 8,50.1")))
        #expect(points(result).count == 2)
        let kinds = Dictionary(uniqueKeysWithValues: result.warnings.map { ($0.kind, $0.count) })
        #expect(kinds[.invalidCoordinate] == 1)
        #expect(kinds[.malformedRecord] == 4)
    }

    /// Scenario "Abgeschnittene Datei".
    @Test func truncatedFileIsAnErrorWithLine() {
        let text = kml(path("8,50 8,50.1 8,50.2"))
        let truncated = String(text.prefix(text.count - 60))
        #expect {
            try read(truncated)
        } throws: { error in
            guard let error = error as? GPSLoggerError, case .malformed(let line) = error.kind else { return false }
            return error.fileName == "tour.kml" && line != nil
        }
    }

    @Test func otherRootIsAnError() {
        #expect(throws: GPSLoggerError.self) { try read("<gpx></gpx>") }
    }

    @Test func largeFileStopsSoonAfterCancellation() async throws {
        let placemark = path("8.000001,50.000001,100 8.000002,50.000002,100", name: "p")
        let big = FileInput(name: "big.kml", data: Data(kml(String(repeating: placemark, count: 420_000)).utf8))
        #expect(big.data.count > 50_000_000)
        let task = Task { try await FileFormats.read([big], format: KMLFileFormat()) }
        task.cancel()
        let start = Date()
        let result = await task.result
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(throws: CancellationError.self) { try result.get() }
    }
}

@Suite("KML – altitude, names and waypoints")
struct KMLDetailTests {
    /// Scenario "Export ohne Höhenbezug".
    @Test func altitudeWithoutMode() throws {
        #expect(points(try read(kml(path("8,50,100 8,50.1,101 8,50.2,102")))).map(\.elevation) == [100, 101, 102])
        let absolute = path("8,50,100 8,50.1,0", extra: "<altitudeMode>absolute</altitudeMode>")
        #expect(points(try read(kml(absolute))).map(\.elevation) == [100, 0])
    }

    /// Scenario "Am Boden" and the other explicit references.
    @Test func groundReferenceDropsAltitude() throws {
        for mode in ["<altitudeMode>clampToGround</altitudeMode>", "<altitudeMode>relativeToGround</altitudeMode>",
                     "<gx:altitudeMode>clampToSeaFloor</gx:altitudeMode>", "<gx:altitudeMode>relativeToSeaFloor</gx:altitudeMode>"] {
            #expect(points(try read(kml(path("8,50,100", extra: mode)))).map(\.elevation) == [nil], "\(mode)")
        }
        let track = "<Placemark><gx:Track><gx:altitudeMode>relativeToSeaFloor</gx:altitudeMode>"
            + "<when>2026-05-01T08:00:00Z</when><gx:coord>8 50 7</gx:coord></gx:Track></Placemark>"
        #expect(points(try read(kml(track))).map(\.elevation) == [nil])
    }

    /// Scenario "Nur Nullen".
    @Test func allZeroAltitudesAreDropped() throws {
        #expect(points(try read(kml(path("8,50,0 8,50.1,0")))).map(\.elevation) == [nil, nil])
        #expect(points(try read(kml(path("8,50 8,50.1")))).map(\.elevation) == [nil, nil])
    }

    /// Scenario "Track aus gpsbabel" (name part) and scenario "Pfad ohne Namen".
    @Test func trackNames() throws {
        let fromFolder = try read(kml("<Folder><name>Morgenrunde</name>\(path("8,50 8,50.1", name: "Path"))</Folder>"))
        #expect(fromFolder.recording.tracks.map(\.name) == ["Morgenrunde"])
        let fromFile = try read(kml(path("8,50 8,50.1")), name: "tour.kml")
        #expect(fromFile.recording.tracks.map(\.name) == ["tour"])
        let own = try read(kml("<name>Doc</name><Folder><name>Ordner</name>\(path("8,50", name: "Eigen"))</Folder>"))
        #expect(own.recording.tracks.map(\.name) == ["Eigen"])
        let fromDocument = try read(kml("<name>Doc</name><Folder>\(path("8,50"))</Folder>"))
        #expect(fromDocument.recording.tracks.map(\.name) == ["Doc"])
    }

    /// A `name` in `Style` or `ExtendedData` is not the track name.
    @Test func nestedNamesDoNotCount() throws {
        let body = "<Placemark><Style><name>Stil</name></Style><ExtendedData><Data name=\"a\"><name>Daten</name></Data></ExtendedData>"
            + "<LineString><coordinates>8,50</coordinates></LineString></Placemark>"
        #expect(try read(kml(body)).recording.tracks.map(\.name) == ["tour"])
    }

    /// Scenario "Markierung mit Beschreibung".
    @Test func waypointWithDescription() throws {
        let body = "<Placemark><name>Hütte</name><description>Rast</description><Point><coordinates>8.1,50.2,300</coordinates></Point></Placemark>"
        let result = try read(kml(body))
        #expect(result.recording.waypoints == [Waypoint(latitude: 50.2, longitude: 8.1, elevation: 300, name: "Hütte", comment: "Rast")])
        #expect(result.recording.tracks.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    /// Scenario "Zeitgestempelte Punkte"; an unreadable waypoint time is dropped silently.
    @Test func timestampedPointsStayWaypoints() throws {
        let marks = (0..<5).map { "<Placemark><name>F\($0)</name><TimeStamp><when>2026-05-01T08:0\($0):00Z</when></TimeStamp><Point><coordinates>8,50.\($0)</coordinates></Point></Placemark>" }
        let result = try read(kml("<Folder><name>Fotos</name>\(marks.joined())</Folder>"
            + "<Placemark><TimeStamp><when>bald</when></TimeStamp><Point><coordinates>8,51</coordinates></Point></Placemark>"))
        #expect(result.recording.tracks.isEmpty)
        #expect(result.recording.waypoints.count == 6)
        #expect(result.recording.waypoints[4].time == time("2026-05-01T08:04:00Z"))
        #expect(result.recording.waypoints[5].time == nil)
        #expect(result.warnings.isEmpty)
    }

    /// Scenario "Gebietsgrenze".
    @Test func polygonIsIgnored() throws {
        let polygon = "<Placemark><name>Gebiet</name><Polygon><outerBoundaryIs><LinearRing><coordinates>8,50 9,50 9,51 8,50</coordinates></LinearRing></outerBoundaryIs></Polygon></Placemark>"
        let result = try read(kml(polygon + path("8,50 8,50.1", name: "Weg")))
        #expect(result.recording.tracks.map(\.name) == ["Weg"])
        #expect(result.recording.waypoints.isEmpty)
        #expect(result.warnings.map(\.kind) == [.missingTimes])
    }

    /// Scenario "Netzwerk-Link".
    @Test func networkLinkIsNotFetched() {
        let body = "<NetworkLink><name>Live</name><Link><href>http://127.0.0.1:9/tracks.kml</href></Link></NetworkLink>"
        #expect {
            try FileFormats.readSynchronously([FileInput(name: "live.kml", data: Data(kml(body).utf8))], format: KMLFileFormat())
        } throws: { error in
            (error as? GPSLoggerError)?.kind == .noUsableData
        }
    }

    /// Scenario "Alte Google-Earth-Datei" and a file without namespace.
    @Test func namespaces() throws {
        let body = path("8,50,100 8,50.1,101", name: "Alt") + "<Placemark><name>P</name><Point><coordinates>8,50</coordinates></Point></Placemark>"
        let reference = try read(kml(body)).recording
        for namespace in ["http://earth.google.com/kml/2.0", "http://earth.google.com/kml/2.1", "http://earth.google.com/kml/2.2", nil] {
            #expect(try read(kml(body, namespace: namespace)).recording == reference, "\(namespace ?? "none")")
        }
    }

    /// A `gx` prefix that is not declared: `XMLParser` accepts it and reports the local name, so the
    /// track is read.
    @Test func undeclaredPrefixIsRead() throws {
        let text = "<kml xmlns=\"\(kml22)\"><Placemark><gx:Track><when>2026-05-01T08:00:00Z</when><gx:coord>8 50 1</gx:coord></gx:Track></Placemark></kml>"
        let result = try read(text)
        #expect(points(result).map(\.time) == [time("2026-05-01T08:00:00Z")])
    }
}

@Suite("KML – gpsbabel points folder")
struct KMLPointsFolderTests {
    private let segments: [[(Double, Double)]] = [
        [(50, 8), (50.001, 8), (50.002, 8)], [(50.003, 8), (50.004, 8), (50.005, 8)],
    ]

    private func stamps(_ count: Int) -> [String] {
        (0..<count).map { String(format: "2026-05-01T08:00:%02dZ", $0 * 5) }
    }

    /// Scenario "Standardausgabe von gpsbabel".
    @Test func gpsbabelOutputGetsTimes() throws {
        let all = segments.flatMap { $0 }
        let marks = zip(all, stamps(6)).map { ($0.0, $0.1, $1) }
        let result = try read(kml(gpsbabelTrack(name: "Lauf", segments: segments, points: marks)))
        #expect(result.recording.tracks.map(\.name) == ["Lauf"])
        #expect(result.recording.tracks[0].segments.map(\.points.count) == [3, 3])
        #expect(result.recording.tracks[0].segments.flatMap(\.points).map(\.time) == stamps(6).map(time))
        #expect(result.recording.waypoints.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    /// Scenario "Punkte passen nicht".
    @Test func mismatchingCountKeepsWaypoints() throws {
        let all = segments.flatMap { $0 }
        let marks = zip(all.prefix(5), stamps(5)).map { ($0.0, $0.1, $1) }
        let result = try read(kml(gpsbabelTrack(name: "Lauf", segments: segments, points: marks)))
        #expect(result.recording.tracks[0].segments.flatMap(\.points).allSatisfy { $0.time == nil })
        #expect(result.recording.waypoints.count == 5)
        #expect(result.warnings.map(\.kind) == [.missingTimes])
    }

    /// A deviation of 0.00001° breaks the match.
    @Test func deviatingCoordinatesKeepWaypoints() throws {
        var all = segments.flatMap { $0 }
        all[4].0 += 0.00001
        let marks = zip(all, stamps(6)).map { ($0.0, $0.1, $1) }
        let result = try read(kml(gpsbabelTrack(name: "Lauf", segments: segments, points: marks)))
        #expect(result.recording.waypoints.count == 6)
        #expect(points(result).allSatisfy { $0.time == nil })
    }

    @Test func pointWithoutTimeKeepsWaypoints() throws {
        let all = segments.flatMap { $0 }
        var times = stamps(6)
        times[2] = "unbekannt"
        let marks = zip(all, times).map { ($0.0, $0.1, $1) }
        let result = try read(kml(gpsbabelTrack(name: "Lauf", segments: segments, points: marks)))
        #expect(result.recording.waypoints.count == 6)
    }
}

@Suite("KML – detection")
struct KMLDetectionTests {
    /// Scenario "KML mit Endung .xml".
    @Test func kmlWithXMLExtension() {
        let data = Data(kml(path("8,50")).utf8)
        #expect(FileFormats.detect(prefix: data, fileName: "export.xml")?.id == .kml)
        #expect(FileFormats.detect(prefix: data, fileName: "export")?.id == .kml)
        #expect(FileFormats.detect(prefix: Data("<gpx></gpx>".utf8), fileName: "a.kml")?.id == .gpx)
    }

    @Test func kmzIsDetected() {
        let archive = KMZTestFile(entries: [KMZTestFile.Entry("doc.kml", pathKML())])
        #expect(FileFormats.detect(prefix: Data(archive.bytes()), fileName: "tour.zip")?.id == .kml)
    }

    /// Scenario "Anderes ZIP-Archiv".
    @Test func otherZIPIsNotKML() {
        let docx = KMZTestFile(entries: [KMZTestFile.Entry("[Content_Types].xml", "<Types/>"), KMZTestFile.Entry("word/document.xml", "<w:document/>")])
        #expect(!KMLFileFormat().matches(prefix: Data(docx.bytes())))
        #expect(FileFormats.detect(prefix: Data(docx.bytes()), fileName: "brief.docx") == nil)
    }

    /// Several files form one recording in the given order; KML and KMZ can be mixed.
    @Test func severalFiles() throws {
        let archive = KMZTestFile(entries: [KMZTestFile.Entry("doc.kml", pathKML(name: "B"))])
        let result = try KMLFileFormat().read([
            FileInput(name: "a.kml", data: Data(kml(path("8,50 8,50.1", name: "A")).utf8)),
            FileInput(name: "b.kmz", data: Data(archive.bytes())),
        ])
        #expect(result.recording.tracks.map(\.name) == ["A", "B"])
        #expect(result.warnings.map(\.fileName) == ["a.kml", "b.kmz"])
    }
}
