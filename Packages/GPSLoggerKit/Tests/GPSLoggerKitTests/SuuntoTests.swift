import Foundation
import Testing
@testable import GPSLoggerKit

private func sml(_ samples: String) -> String {
    "<?xml version=\"1.0\" encoding=\"utf-8\"?><sml xmlns=\"http://www.suunto.com/schemas/sml\"><DeviceLog>"
        + "<Header><Duration>1</Duration></Header><Samples>\(samples)</Samples></DeviceLog></sml>"
}

private func gps(lat: String = "0.8726646259971648", lon: String = "0.17453292519943295",
                 utc: String? = "2026-05-01T08:00:00Z", extra: String = "") -> String {
    "<Sample>\(utc.map { "<UTC>\($0)</UTC>" } ?? "")<Latitude>\(lat)</Latitude><Longitude>\(lon)</Longitude>"
        + "\(extra)<SampleType>gps-base</SampleType></Sample>"
}

private func periodic(altitude: Int, utc: String) -> String {
    "<Sample><UTC>\(utc)</UTC><Altitude>\(altitude)</Altitude><Temperature>293</Temperature>"
        + "<SampleType>periodic</SampleType></Sample>"
}

private func pause(_ state: String) -> String {
    "<Sample><UTC>2026-05-01T08:00:00Z</UTC><Events><Pause><Type>30</Type><State>\(state)</State></Pause></Events></Sample>"
}

private func read(_ text: String, name: String = "move.sml") throws -> ImportResult {
    try SuuntoSMLFileFormat().read([FileInput(name: name, data: Data(text.utf8))])
}

private func points(_ result: ImportResult) -> [TrackPoint] {
    result.recording.tracks.flatMap(\.segments).flatMap(\.points)
}

private func fixture(_ name: String) throws -> FileInput {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try FileInput.load(url)
}

@Suite("Suunto SML import")
struct SuuntoTests {
    /// Scenario "GPS-Probe umrechnen".
    @Test func gpsSampleIsConverted() throws {
        let result = try read(sml(gps(extra: "<GPSHeading>3.141592653589793</GPSHeading><NumberOfSatellites>12</NumberOfSatellites>"
                                         + "<GPSSpeed>1.5</GPSSpeed><GpsHDOP>0.7</GpsHDOP>")))
        let point = try #require(points(result).first)
        #expect(abs(point.latitude - 50) < 1e-9)
        #expect(abs(point.longitude - 10) < 1e-9)
        #expect(point.time == ISO8601.date("2026-05-01T08:00:00Z"))
        #expect(abs((point.quality.course ?? 0) - 180) < 1e-9)
        #expect(point.quality.satellites == 12)
        #expect(point.quality.speed == 1.5)
        #expect(point.quality.hdop == 0.7)
        #expect(result.recording.tracks[0].name == "move")
        #expect(result.warnings.isEmpty)
    }

    /// Scenario "Periodische Probe".
    @Test func periodicSampleGivesNoPoint() throws {
        let result = try read(sml(periodic(altitude: 7, utc: "2026-05-01T08:00:00Z")))
        #expect(result.recording.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    /// Scenario "Barometrische Höhe".
    @Test func recentBarometricAltitudeWins() throws {
        let result = try read(sml(periodic(altitude: 118, utc: "2026-05-01T07:59:50Z")
                                  + gps(extra: "<GPSAltitude>130</GPSAltitude>")))
        #expect(points(result).first?.elevation == 118)
    }

    /// Scenario "Nur GPS-Höhe".
    @Test func oldBarometricAltitudeIsNotUsed() throws {
        let result = try read(sml(periodic(altitude: 118, utc: "2026-05-01T07:58:59Z")
                                  + gps(extra: "<GPSAltitude>130</GPSAltitude>")))
        #expect(points(result).first?.elevation == 130)
        #expect(points(try read(sml(gps()))).first?.elevation == nil)
    }

    /// Scenario "Aufzeichnung mit Pause".
    @Test func pausesSplitSegments() throws {
        let samples = String(repeating: gps(), count: 20) + pause("True") + pause("False") + String(repeating: gps(), count: 10)
        let result = try read(sml(samples))
        #expect(result.recording.tracks[0].segments.map(\.points.count) == [20, 10])
    }

    /// Scenario "Startereignis".
    @Test func startEventGivesNoEmptySegment() throws {
        let result = try read(sml(pause("False") + gps() + gps() + pause("True")))
        #expect(result.recording.tracks[0].segments.map(\.points.count) == [2])
    }

    /// Scenario "Ungültige Breite" and unreadable numbers.
    @Test func damagedSamplesAreWarnings() throws {
        let result = try read(sml(gps() + gps(lat: "2.0") + gps(lon: "abc")))
        #expect(points(result).count == 1)
        #expect(result.warnings.map(\.kind) == [.malformedRecord, .invalidCoordinate])
    }

    @Test func missingUTCIsAWarning() throws {
        let result = try read(sml(gps(utc: nil)))
        #expect(points(result).first?.time == nil)
        #expect(result.warnings.map(\.kind) == [.missingDate])
    }

    @Test func headingIsNormalized() {
        #expect(abs(SuuntoSMLFileFormat.degrees(fromHeading: 2 * .pi + .pi / 2) - 90) < 1e-9)
        #expect(abs(SuuntoSMLFileFormat.degrees(fromHeading: -.pi / 2) - 270) < 1e-9)
    }

    @Test(arguments: ["ambit.sml", "ambit.xml"])
    func fixtureIsRead(name: String) throws {
        let result = try SuuntoSMLFileFormat().read([fixture(name)])
        let track = try #require(result.recording.tracks.first)
        #expect(track.name == "ambit")
        #expect(track.segments.map(\.points.count) == [5, 3])
        let all = track.segments.flatMap(\.points)
        #expect(all.map(\.elevation) == [118, 118, 118, 118, 120, 135, 136, 137])
        #expect(all[4].quality.satellites == 7 && all[4].quality.speed == nil)
        #expect(all[0].quality.satellites == 9 && all[0].quality.speed == 2.5)
        #expect(abs((all[0].quality.course ?? 0) - 26.6) < 1e-9)
        #expect(abs(all[0].latitude - 50) < 1e-9 && abs(all[0].longitude - 8) < 1e-9)
        #expect(all[0].time == ISO8601.date("2026-05-01T08:00:10Z"))
        #expect(result.warnings.isEmpty)
    }

    /// Scenario "Abgeschnittene Datei".
    @Test func truncatedFileIsAnErrorWithLine() throws {
        let text = String(decoding: try fixture("ambit.sml").data, as: UTF8.self)
        let truncated = String(text.prefix(text.count / 2))
        #expect {
            try read(truncated)
        } throws: { error in
            guard let error = error as? GPSLoggerError, case .malformed(let line) = error.kind else { return false }
            return error.fileName == "move.sml" && line != nil
        }
    }

    /// Scenario "SML mit Endung .xml".
    @Test func detection() throws {
        let data = try fixture("ambit.xml").data
        #expect(FileFormats.detect(prefix: data, fileName: "ambit.xml")?.id == .suuntoSML)
        #expect(FileFormats.detect(prefix: data, fileName: "ambit")?.id == .suuntoSML)
        #expect(FileFormats.detect(prefix: Data("<gpx></gpx>".utf8), fileName: "a.sml")?.id == .gpx)
    }

    @Test func largeFileStopsSoonAfterCancellation() async throws {
        let big = FileInput(name: "big.sml", data: Data(sml(String(repeating: gps(), count: 400_000)).utf8))
        #expect(big.data.count > 50_000_000)
        let task = Task { try await FileFormats.read([big], format: SuuntoSMLFileFormat()) }
        task.cancel()
        let start = Date()
        let result = await task.result
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(throws: CancellationError.self) { try result.get() }
    }
}
