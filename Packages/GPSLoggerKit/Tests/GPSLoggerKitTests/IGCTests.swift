import Foundation
import Testing
@testable import GPSLoggerKit

private let header = "AXXX001\nHFDTE020726\n"

private func read(_ files: [(String, String)]) throws -> ImportResult {
    try FileFormats.readSynchronously(files.map { FileInput(name: $0.0, data: Data($0.1.utf8)) },
                                      format: IGCFileFormat(), options: ImportOptions(correctWeekRollover: false))
}

private func read(_ text: String) throws -> ImportResult {
    try read([("t.igc", text)])
}

private func points(_ result: ImportResult) -> [TrackPoint] {
    result.recording.tracks.flatMap(\.segments).flatMap(\.points)
}

private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Double) -> Date {
    UTCTime.date(year: y, month: mo, day: d, hour: h, minute: mi, second: s)!
}

/// Builds a B record from its fields.
private func b(_ time: String = "110135", lat: String = "5206343N", lon: String = "00006198W", valid: String = "A",
               pressure: String = "00587", gnss: String = "00558", extensions: String = "") -> String {
    "B\(time)\(lat)\(lon)\(valid)\(pressure)\(gnss)\(extensions)"
}

private func fixture(_ name: String) throws -> FileInput {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return FileInput(name: name, data: try Data(contentsOf: url))
}

@Suite("IGC – fixes")
struct IGCFixTests {
    /// Scenario "Gültiger Fix".
    @Test func validFix() throws {
        let result = try read(header + "B1101355206343N00006198WA0058700558\n")
        let point = try #require(points(result).first)
        #expect(abs(point.latitude - 52.105717) < 0.000001)
        #expect(abs(point.longitude - -0.1033) < 0.000001)
        #expect(point.time == utc(2026, 7, 2, 11, 1, 35))
        #expect(point.elevation == 558)
        #expect(point.quality.fix == .threeD)
        #expect(result.warnings.isEmpty)
    }

    /// Scenario "Südlich und östlich".
    @Test func southAndEast() throws {
        let point = try #require(points(try read(header + b(lat: "3352000S", lon: "15112500E") + "\n")).first)
        #expect(abs(point.latitude - -33.866667) < 0.000001)
        #expect(abs(point.longitude - 151.208333) < 0.000001)
    }

    /// Scenario "Abgeschnittener Datensatz".
    @Test func truncatedRecordIsCounted() throws {
        let result = try read(header + b() + "\n" + "B1101405206400N0000\n" + b("110145") + "\n")
        #expect(points(result).count == 2)
        #expect(result.warnings.map(\.kind) == [.malformedRecord])
        #expect(result.warnings.first?.count == 1)
        #expect(result.warnings.first?.firstLine == 4)
    }

    @Test func invalidDigitsOrLettersAreMalformed() throws {
        let result = try read(header + [
            b("11x135"), b("250000"), b(lat: "5206343X"), b(valid: "Z"), b(gnss: "0055x"), b("110200"),
        ].joined(separator: "\n"))
        #expect(points(result).count == 1)
        #expect(result.warnings.first { $0.kind == .malformedRecord }?.count == 5)
    }

    @Test func minutesOfSixtyOrMoreAreInvalidCoordinates() throws {
        let result = try read(header + b(lat: "5260000N") + "\n" + b(lon: "18100000E") + "\n" + b(lat: "9100000N") + "\n" + b() + "\n")
        #expect(points(result).count == 1)
        #expect(result.warnings.map(\.kind) == [.invalidCoordinate])
        #expect(result.warnings.first?.count == 3)
    }

    @Test func negativeAltitudes() throws {
        let point = try #require(points(try read(header + b(pressure: "-0020", gnss: "-0012") + "\n")).first)
        #expect(point.elevation == -12)
        let fallback = try #require(points(try read(header + b(valid: "V", pressure: "-0020", gnss: "00000") + "\n")).first)
        #expect(fallback.elevation == -20)
    }
}

@Suite("IGC – altitude and fix")
struct IGCAltitudeTests {
    /// Scenario "Gerät ohne Drucksensor".
    @Test func gnssAltitudeWithoutPressureSensor() throws {
        let point = try #require(points(try read(header + b(valid: "A", pressure: "00000", gnss: "00412") + "\n")).first)
        #expect(point.elevation == 412)
        #expect(point.quality.fix == .threeD)
    }

    /// Scenario "Fix ohne GNSS-Höhe".
    @Test func pressureAltitudeWhenFixIsTwoD() throws {
        let point = try #require(points(try read(header + b(valid: "V", pressure: "00380", gnss: "00000") + "\n")).first)
        #expect(point.elevation == 380)
        #expect(point.quality.fix == .twoD)
    }

    /// A `V` fix ignores a non-zero GNSS altitude in favour of the pressure altitude.
    @Test func invalidFixPrefersPressureAltitude() throws {
        let point = try #require(points(try read(header + b(valid: "V", pressure: "00380", gnss: "00999") + "\n")).first)
        #expect(point.elevation == 380)
    }

    /// Scenario "Keine Höhe".
    @Test func noAltitude() throws {
        let point = try #require(points(try read(header + b(pressure: "00000", gnss: "00000") + "\n")).first)
        #expect(point.elevation == nil)
    }
}

@Suite("IGC – extensions")
struct IGCExtensionTests {
    /// Scenario "Satelliten".
    @Test func satellitesFromSIU() throws {
        let point = try #require(points(try read(header + "I023638FXA3940SIU\n" + b(extensions: "02509") + "\n")).first)
        #expect(point.quality.satellites == 9)
    }

    /// Scenario "Unbekannte Erweiterung".
    @Test func unknownExtensionsAreSkipped() throws {
        let result = try read(header + "I023638GSP3941TRT\n" + b(extensions: "045180") + "\n")
        #expect(points(result).first?.quality.satellites == nil)
        #expect(result.warnings.isEmpty)
    }

    @Test func recordShorterThanExtensionStillCounts() throws {
        let result = try read(header + "I023638FXA3940SIU\n" + b(extensions: "02") + "\n")
        #expect(points(result).count == 1)
        #expect(points(result).first?.quality.satellites == nil)
        #expect(result.warnings.isEmpty)
    }

    @Test func invalidIRecordIsCountedAndIgnored() throws {
        let result = try read(header + "I0236\n" + b(extensions: "02509") + "\n")
        #expect(points(result).count == 1)
        #expect(points(result).first?.quality.satellites == nil)
        #expect(result.warnings.map(\.kind) == [.malformedRecord])
    }
}

@Suite("IGC – date, tracks and other records")
struct IGCDateTests {
    /// Scenario "Neue Schreibweise".
    @Test func newDateForm() throws {
        let point = try #require(points(try read("AXXX001\nHFDTEDATE:150726,01\n" + b() + "\n")).first)
        #expect(point.time == utc(2026, 7, 15, 11, 1, 35))
    }

    @Test func twoDigitYears() throws {
        let old = try #require(points(try read("AXXX001\nHFDTE010185\n" + b() + "\n")).first)
        #expect(old.time == utc(1985, 1, 1, 11, 1, 35))
    }

    /// Scenario "Flug über Mitternacht".
    @Test func flightOverMidnight() throws {
        let result = try read("AXXX001\nHFDTE311225\n" + b("235958") + "\n" + b("000002") + "\n")
        #expect(points(result).map(\.time) == [utc(2025, 12, 31, 23, 59, 58), utc(2026, 1, 1, 0, 0, 2)])
    }

    /// Scenario "Fehlendes Datum".
    @Test func missingDate() throws {
        let result = try read("AXXX001\n" + b() + "\n" + b("110140") + "\n")
        #expect(points(result).count == 2)
        #expect(points(result).allSatisfy { $0.time == nil })
        #expect(result.warnings.map(\.kind) == [.missingDate])
        #expect(result.warnings.first?.count == 2)
    }

    @Test func invalidDateIsCounted() throws {
        let result = try read("AXXX001\nHFDTE320726\n" + b() + "\n")
        #expect(Set(result.warnings.map(\.kind)) == [.malformedRecord, .missingDate])
    }

    /// Scenario "Zwei Flüge".
    @Test func oneTrackPerFile() throws {
        let result = try read([("flug1.igc", header + b() + "\n"), ("flug2.igc", header + b("120000") + "\n")])
        #expect(result.recording.tracks.map(\.name) == ["flug1", "flug2"])
        #expect(result.recording.tracks.allSatisfy { $0.segments.count == 1 })
    }

    @Test func trackName() {
        #expect(IGCFileFormat.trackName(for: "dir/2026-07-02 flight.IGC") == "2026-07-02 flight")
        #expect(IGCFileFormat.trackName(for: "noextension") == "noextension")
    }

    /// Scenarios "Aufgabendeklaration" and "Signatur".
    @Test func otherRecordsAreIgnored() throws {
        let text = header + "C020726120000020726000102\nC5206343N00006198WTakeoff\nE110135PEV\nF1101350102\nLPLTx\n"
            + "K110135123\n" + b() + "\nGABCDEF0123456789\nGXYZ\n"
        let result = try read(text)
        #expect(points(result).count == 1)
        #expect(result.recording.waypoints.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    @Test func noFixesMeansNoUsableData() {
        #expect(throws: GPSLoggerError(.noUsableData, fileName: "t.igc")) { try read(header + "LPLTx\n") }
    }

    /// Scenario "Große Datei abbrechen" for IGC.
    @Test func stopsSoonAfterCancellation() async throws {
        let file = FileInput(name: "big.igc", data: Data((header + String(repeating: b() + "\r\n", count: 600_000)).utf8))
        let task = Task { try await FileFormats.read([file], format: IGCFileFormat()) }
        task.cancel()
        let start = Date()
        let result = await task.result
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(throws: CancellationError.self) { try result.get() }
    }
}

@Suite("IGC – detection")
struct IGCDetectionTests {
    private let igc = Data((header + "B1101355206343N00006198WA0058700558\n").utf8)

    @Test func detectedByContent() {
        #expect(FileFormats.detect(prefix: igc, fileName: "flight.igc")?.id == .igc)
    }

    /// Scenario "Endung fehlt".
    @Test func detectedWithWrongExtension() {
        #expect(FileFormats.detect(prefix: igc, fileName: "flight.txt")?.id == .igc)
    }

    /// Scenario "Keine IGC-Datei".
    @Test func nmeaWithIGCExtension() {
        let text = (0..<3).map { _ in nmea("GPGGA,120000,5144.4694,N,00840.8580,E,1,08,0.9,94.5,M,47.0,M,,") }
            .joined(separator: "\n")
        #expect(FileFormats.detect(prefix: Data(text.utf8), fileName: "track.igc")?.id == .nmea)
    }

    @Test func textStartingWithAIsNotIGC() {
        #expect(!IGCFileFormat().matches(prefix: Data("A list of things\nsecond line\n".utf8)))
        #expect(!IGCFileFormat().matches(prefix: Data("AXXX001\n".utf8)))
        #expect(!IGCFileFormat().matches(prefix: Data("HFDTE020726\nB1101355206343N00006198WA0058700558\n".utf8)))
        #expect(IGCFileFormat().matches(prefix: Data("\r\n  \r\nAXXX001\r\nHFDTE020726\r\n".utf8)))
    }

    @Test func existingFixturesKeepTheirFormat() throws {
        for (name, id) in [("canon-eos.LOG", FileFormatID.nmea), ("sony-cs1.log", .nmea), ("garmin-gpx10.gpx", .gpx),
                           ("garmin-oregon.gpx", .gpx), ("flight-crlf.igc", .igc), ("flight-midnight.igc", .igc)] {
            let file = try fixture(name)
            #expect(FileFormats.detect(prefix: file.data, fileName: "unknown.dat")?.id == id, "\(name)")
        }
    }
}

@Suite("IGC – fixtures")
struct IGCFixtureTests {
    @Test func flightWithAllRecordTypes() throws {
        let result = try FileFormats.readSynchronously([try fixture("flight-crlf.igc")], format: IGCFileFormat(),
                                                       options: ImportOptions(correctWeekRollover: false))
        #expect(result.warnings.isEmpty)
        #expect(result.recording.tracks.map(\.name) == ["flight-crlf"])
        let all = points(result)
        #expect(all.count == 4)
        let first = try #require(all.first), last = try #require(all.last)
        #expect(abs(first.latitude - 52.105717) < 0.000001 && abs(first.longitude - -0.1033) < 0.000001)
        #expect(abs(last.latitude - 52.108667) < 0.000001 && abs(last.longitude - -0.098333) < 0.000001)
        #expect(first.time == utc(2026, 7, 2, 11, 1, 35))
        #expect(last.time == utc(2026, 7, 2, 11, 1, 50))
        #expect(last.elevation == 570)
        #expect(last.quality.satellites == 10)
    }

    @Test func flightOverMidnightWithoutPressureSensor() throws {
        let result = try FileFormats.readSynchronously([try fixture("flight-midnight.igc")], format: IGCFileFormat(),
                                                       options: ImportOptions(correctWeekRollover: false))
        #expect(result.warnings.isEmpty)
        let all = points(result)
        #expect(all.count == 4)
        #expect(abs(all[0].latitude - -1.033333) < 0.000001 && all[0].longitude == 36.5)
        #expect(all.first?.time == utc(2025, 12, 31, 23, 59, 58))
        #expect(all.last?.time == utc(2026, 1, 1, 0, 0, 2))
        #expect(all.map(\.elevation) == [412, 413, 414, 415])
        #expect(all.allSatisfy { $0.quality.satellites == nil && $0.quality.fix == .threeD })
    }

    #if os(macOS)
    @Test func gpxFromIGCIsSchemaValid() throws {
        let result = try FileFormats.readSynchronously([try fixture("flight-crlf.igc"), try fixture("flight-midnight.igc")],
                                                       format: IGCFileFormat())
        let data = try GPXWriter(creator: "GPSLoggerKit tests").data(for: result.recording, createdAt: Date())
        try GPXSchemaValidator.validate(data)
    }
    #endif
}
