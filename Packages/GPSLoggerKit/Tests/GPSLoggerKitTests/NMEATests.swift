import Foundation
import Testing
@testable import GPSLoggerKit

/// Builds a sentence with a correct checksum: `nmea("GPRMC,...")` -> `$GPRMC,...*hh`.
func nmea(_ body: String) -> String {
    let checksum = body.utf8.reduce(UInt8(0)) { $0 ^ $1 }
    return "$" + body + "*" + String(format: "%02X", checksum)
}

private func read(_ files: [(String, String)], options: ImportOptions = ImportOptions(correctWeekRollover: false)) throws -> ImportResult {
    try FileFormats.readSynchronously(files.map { FileInput(name: $0.0, data: Data($0.1.utf8)) },
                                      format: NMEAFileFormat(), options: options)
}

private func read(_ text: String) throws -> ImportResult {
    try read([("t.nmea", text)])
}

private func points(_ result: ImportResult) -> [TrackPoint] {
    result.recording.tracks.flatMap(\.segments).flatMap(\.points)
}

private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Double) -> Date {
    UTCTime.date(year: y, month: mo, day: d, hour: h, minute: mi, second: s)!
}

private func rmc(_ time: String, date: String = "021126", status: String = "A", lat: String = "5144.4694,N",
                 lon: String = "00840.8580,E", knots: String = "10.0", course: String = "90.0") -> String {
    nmea("GPRMC,\(time),\(status),\(lat),\(lon),\(knots),\(course),\(date),,,A")
}

private func gga(_ time: String, quality: String = "1", sats: String = "08", hdop: String = "0.9",
                 alt: String = "94.5", lat: String = "5144.4694,N", lon: String = "00840.8580,E", talker: String = "GP") -> String {
    nmea("\(talker)GGA,\(time),\(lat),\(lon),\(quality),\(sats),\(hdop),\(alt),M,47.0,M,,")
}

@Suite("NMEA – lines and checksums")
struct NMEALineTests {
    @Test(arguments: ["\n", "\r\n", "\r"])
    func lineTerminators(terminator: String) throws {
        let text = [rmc("120000"), rmc("120001"), rmc("120002")].joined(separator: terminator)
        #expect(points(try read(text)).count == 3)
    }

    /// Scenario "Sony-Logdatei".
    @Test func atLinesAreSkipped() throws {
        let text = "@Sonygps/ver1.0/wgs-84\n" + rmc("120000") + "\n@Sonygps/ver1.0/wgs-84\n" + gga("120001") + "\n"
        let result = try read(text)
        #expect(points(result).count == 2)
        #expect(result.warnings.isEmpty)
    }

    /// Scenario "Falsche Prüfsumme".
    @Test func wrongChecksumIsSkippedAndCounted() throws {
        var broken = rmc("120001")
        broken.replaceSubrange(broken.index(broken.endIndex, offsetBy: -2)..., with: "00")
        let result = try read([rmc("120000"), broken, rmc("120002")].joined(separator: "\n"))
        #expect(points(result).count == 2)
        #expect(result.warnings == [ImportWarning(kind: .checksumMismatch, count: 1, fileName: "t.nmea", firstLine: 2)])
    }

    @Test func sentencesWithoutChecksumAreAccepted() throws {
        let text = "$GPRMC,120000,A,5144.4694,N,00840.8580,E,10.0,90.0,021126,,,A\n"
        #expect(points(try read(text)).count == 1)
    }

    /// Scenario "Abgeschnittene letzte Zeile".
    @Test func truncatedLastLineIsDropped() throws {
        let text = rmc("120000") + "\n" + rmc("120001") + "\n$GPRMC,120002,A,5144.46"
        let result = try read(text)
        #expect(points(result).count == 2)
        #expect(result.warnings.map(\.kind) == [.malformedRecord])
    }

    /// Scenario "Multi-GNSS-Logger".
    @Test(arguments: ["GN", "GL", "GA", "GB", "BD", "GQ"])
    func anyTalkerIsAccepted(talker: String) throws {
        let text = nmea("\(talker)RMC,120000,A,5144.4694,N,00840.8580,E,10.0,90.0,021126,,,A") + "\n"
            + gga("120000", talker: talker)
        let result = try read(text)
        #expect(points(result).count == 1)
        #expect(points(result).first?.elevation == 94.5)
    }

    /// Scenario "Satellitenstatus".
    @Test func gsvAndProprietarySentencesAreIgnoredSilently() throws {
        let text = [rmc("120000"),
                    nmea("GPGSV,3,1,11,03,03,111,00,04,15,270,00,06,01,010,00,13,06,292,00"),
                    nmea("PMTK001,604,3"),
                    nmea("PSRF103,00,01,00,01")].joined(separator: "\n")
        let result = try read(text)
        #expect(points(result).count == 1)
        #expect(result.warnings.isEmpty)
    }

    @Test func binaryGarbageIsIgnored() throws {
        var data = Data([0xEF, 0xBB, 0xBF, 0x00, 0xFF, 0x0A])
        data += Data((rmc("120000") + "\n").utf8)
        data += Data([0xA0, 0xA2, 0x00, 0x0A])
        let result = try FileFormats.readSynchronously([FileInput(name: "b", data: data)], format: NMEAFileFormat(),
                                                       options: ImportOptions(correctWeekRollover: false))
        #expect(points(result).count == 1)
    }
}

@Suite("NMEA – fields")
struct NMEAFieldTests {
    @Test func rmcValues() throws {
        let point = try #require(points(try read(rmc("143005.250", knots: "10.0", course: "271.5"))).first)
        #expect(abs(point.latitude - 51.741156666) < 1e-6)
        #expect(abs(point.longitude - 8.680966666) < 1e-6)
        #expect(point.time == utc(2026, 11, 2, 14, 30, 5.25))
        #expect(abs((point.quality.speed ?? 0) - 5.144444) < 1e-5)
        #expect(point.quality.course == 271.5)
    }

    @Test func southernAndWesternHemisphere() throws {
        let point = try #require(points(try read(rmc("120000", lat: "3351.1234,S", lon: "15112.5678,W"))).first)
        #expect(point.latitude < -33.85 && point.latitude > -33.86)
        #expect(point.longitude < -151.20 && point.longitude > -151.21)
    }

    @Test func emptyOptionalFieldsStayEmpty() throws {
        let point = try #require(points(try read(rmc("120000", knots: "", course: ""))).first)
        #expect(point.quality.speed == nil)
        #expect(point.quality.course == nil)
        #expect(point.elevation == nil)
    }

    @Test func outOfRangeCoordinateIsAWarning() throws {
        let result = try read([rmc("120000"), rmc("120001", lat: "9512.0000,N"), rmc("120002", lon: "00861.0000,E")].joined(separator: "\n"))
        #expect(points(result).count == 1)
        #expect(result.warnings.map(\.kind) == [.invalidCoordinate])
        #expect(result.warnings.first?.count == 2)
    }

    /// Scenario "Logger ohne Empfang".
    @Test func onlyValidFixes() throws {
        var lines = (0..<50).map { rmc(String(format: "1200%02d", $0), status: "V", lat: ",", lon: ",") }
        lines += (0..<10).map { rmc(String(format: "1201%02d", $0)) }
        lines.append(gga("120200", quality: "0"))
        lines.append(nmea("GPGLL,5144.4694,N,00840.8580,E,120300,V,N"))
        let result = try read(lines.joined(separator: "\n"))
        #expect(points(result).count == 10)
        #expect(result.warnings.isEmpty)
    }

    @Test func gllIsAPositionSource() throws {
        let result = try read([rmc("115959"), nmea("GPGLL,5144.4694,N,00840.8580,E,120000.00,A,A")].joined(separator: "\n"))
        #expect(points(result).count == 2)
        #expect(points(result).last?.time == utc(2026, 11, 2, 12, 0, 0))
    }

    @Test func gsaGivesFixAndDOP() throws {
        let text = [rmc("120000"), gga("120000", hdop: ""),
                    nmea("GPGSA,A,3,04,05,,09,12,,,24,,,,,2.5,1.3,2.1")].joined(separator: "\n")
        let point = try #require(points(try read(text)).first)
        #expect(point.quality.fix == .threeD)
        #expect(point.quality.pdop == 2.5)
        #expect(point.quality.hdop == 1.3)
        #expect(point.quality.vdop == 2.1)
        #expect(point.quality.satellites == 8)
    }

    @Test func ggaDGPSQuality() throws {
        let point = try #require(points(try read(rmc("120000") + "\n" + gga("120000", quality: "2"))).first)
        #expect(point.quality.fix == .dgps)
    }

    @Test(arguments: [
        "GPVTG,054.7,T,034.4,M,005.5,N,010.2,K,A",  // NMEA 2.3+
        "GPVTG,054.7,T,034.4,M,005.5,N,010.2,K",    // NMEA 2.0
        "GPVTG,054.7,034.4,005.5,010.2",            // old form without unit letters
    ])
    func vtgSuppliesSpeedAndCourseWhenRMCHasNone(vtg: String) throws {
        let text = gga("120000") + "\n" + nmea(vtg)
        let point = try #require(points(try read([("t", text)], options: ImportOptions(correctWeekRollover: false))).first)
        #expect(point.quality.course == 54.7)
        #expect(abs((point.quality.speed ?? 0) - 2.8333) < 0.01)
    }

    @Test func rmcSpeedWinsOverVTG() throws {
        let text = rmc("120000", knots: "10.0") + "\n" + nmea("GPVTG,054.7,T,034.4,M,005.5,N,010.2,K,A")
        let point = try #require(points(try read(text)).first)
        #expect(abs((point.quality.speed ?? 0) - 5.1444) < 0.001)
        #expect(point.quality.course == 90)
    }

    /// Scenario "WPL-Satz".
    @Test func wplBecomesAWaypoint() throws {
        let result = try read(rmc("120000") + "\n" + nmea("GPWPL,5144.4694,N,00840.8580,E,HOME"))
        let waypoint = try #require(result.recording.waypoints.first)
        #expect(waypoint.name == "HOME")
        #expect(abs(waypoint.latitude - 51.741157) < 1e-6)
        #expect(abs(waypoint.longitude - 8.680967) < 1e-6)
    }

    @Test func fileWithOnlyWaypointsIsUsable() throws {
        let result = try read(nmea("GPWPL,5144.4694,N,00840.8580,E,HOME"))
        #expect(result.recording.tracks.isEmpty)
        #expect(result.recording.waypoints.count == 1)
    }
}

@Suite("NMEA – epochs and dates")
struct NMEADateTests {
    /// Scenario "RMC und GGA zur selben Sekunde".
    @Test func rmcAndGGAOfOneSecondFormOnePoint() throws {
        let result = try read(rmc("120001") + "\n" + gga("120001", sats: "08", alt: "94.5"))
        let point = try #require(points(result).first)
        #expect(points(result).count == 1)
        #expect(point.elevation == 94.5)
        #expect(point.quality.satellites == 8)
        #expect(point.time == utc(2026, 11, 2, 12, 0, 1))
    }

    @Test func ggaBeforeRMCOfTheSameSecondAlsoFormsOnePoint() throws {
        let result = try read(gga("120001") + "\n" + rmc("120001") + "\n" + gga("120002") + "\n" + rmc("120002"))
        #expect(points(result).count == 2)
        #expect(points(result).allSatisfy { $0.elevation == 94.5 && $0.quality.speed != nil })
    }

    /// Scenario "Nur GGA" (with a date from an earlier RMC).
    @Test func onlyGGAGivesOnePointPerSentence() throws {
        let text = ([rmc("115959")] + (0..<5).map { gga(String(format: "1200%02d", $0)) }).joined(separator: "\n")
        #expect(points(try read(text)).count == 6)
    }

    /// Scenario "Mitternacht".
    @Test func midnightAdvancesTheDate() throws {
        let text = [rmc("235959", date: "021126"), gga("000000"), gga("000001")].joined(separator: "\n")
        let times = points(try read(text)).map(\.time)
        #expect(times == [utc(2026, 11, 2, 23, 59, 59), utc(2026, 11, 3, 0, 0, 0), utc(2026, 11, 3, 0, 0, 1)])
    }

    /// Scenario "GGA vor dem ersten RMC".
    @Test func pointsBeforeTheFirstDateGetIt() throws {
        let text = [gga("120000"), gga("120001"), gga("120002"), rmc("120003")].joined(separator: "\n")
        let result = try read(text)
        #expect(points(result).map(\.time) == (0...3).map { utc(2026, 11, 2, 12, 0, Double($0)) })
        #expect(result.warnings.isEmpty)
    }

    @Test func pointsBeforeTheFirstDateAcrossMidnightGetThePreviousDay() throws {
        let text = [gga("235959"), rmc("000000", date: "031126")].joined(separator: "\n")
        #expect(points(try read(text)).map(\.time) == [utc(2026, 11, 2, 23, 59, 59), utc(2026, 11, 3, 0, 0, 0)])
    }

    /// Scenario "Datei ganz ohne Datum".
    @Test func fileWithoutAnyDate() throws {
        let result = try read([gga("120000"), gga("120001"), gga("120002")].joined(separator: "\n"))
        #expect(points(result).count == 3)
        #expect(points(result).allSatisfy { $0.time == nil })
        #expect(result.warnings == [ImportWarning(kind: .missingDate, count: 3, fileName: "t.nmea")])
    }

    @Test func zdaSuppliesTheDate() throws {
        let text = [nmea("GPZDA,120000.00,03,11,2026,00,00"), gga("120000")].joined(separator: "\n")
        #expect(points(try read(text)).first?.time == utc(2026, 11, 3, 12, 0, 0))
    }

    @Test(arguments: [("010180", 1980), ("311279", 2079), ("150307", 2007)])
    func twoDigitYears(date: String, year: Int) throws {
        let time = try #require(points(try read(rmc("120000", date: date))).first?.time)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(calendar.component(.year, from: time) == year)
    }

    @Test func millisecondsArePreserved() throws {
        let times = points(try read([rmc("120000.200"), rmc("120000.400")].joined(separator: "\n"))).map(\.time)
        #expect(times == [utc(2026, 11, 2, 12, 0, 0.2), utc(2026, 11, 2, 12, 0, 0.4)])
    }
}

@Suite("NMEA – tracks and segments")
struct NMEASegmentTests {
    /// Scenario "Drei Dateien eines Tages".
    @Test func threeFilesFormOneTrackWithThreeSegments() throws {
        let files = (0..<3).map { file in
            ("\(file).nmea", (0..<4).map { rmc(String(format: "1%d00%02d", file, $0)) }.joined(separator: "\n"))
        }
        let result = try read(files)
        #expect(result.recording.tracks.count == 1)
        #expect(result.recording.tracks[0].segments.map(\.points.count) == [4, 4, 4])
    }

    @Test func datesDoNotLeakBetweenFiles() throws {
        let result = try read([("a", rmc("120000", date: "021126")), ("b", gga("130000"))])
        #expect(points(result).last?.time == nil)
        #expect(result.warnings.map(\.kind) == [.missingDate])
    }

    /// Scenario "Zeitrücksprung".
    @Test func timeGoingBackwardsStartsANewSegment() throws {
        let text = [rmc("100004"), rmc("100005"), rmc("090000"), rmc("090001")].joined(separator: "\n")
        #expect(try read(text).recording.tracks[0].segments.map(\.points.count) == [2, 2])
    }

    @Test func registeredInTheCatalog() {
        let format = FileFormats.format(withID: .nmea)
        #expect(format is NMEAFileFormat)
        #expect(Set(format?.fileExtensions ?? []) == ["nmea", "nma", "txt", "log", "gps"])
    }
}

@Suite("NMEA – detection")
struct NMEADetectionTests {
    /// Scenario "NMEA mit falscher Endung".
    @Test func nmeaWithTxtExtension() {
        let data = Data(([rmc("120000"), gga("120000"), rmc("120001")].joined(separator: "\n")).utf8)
        #expect(FileFormats.detect(prefix: data, fileName: "log.txt")?.id == .nmea)
        #expect(FileFormats.detect(prefix: data, fileName: "data.gpx")?.id == .nmea)
    }

    /// Scenario "Canon-EOS-Log".
    @Test func canonLogWithHeader() throws {
        let url = try #require(Bundle.module.url(forResource: "canon-eos", withExtension: "LOG", subdirectory: "Fixtures"))
        let input = try FileInput.load(url)
        #expect(FileFormats.detect(prefix: input.data, fileName: input.name)?.id == .nmea)
        let result = try FileFormats.readSynchronously([input], format: NMEAFileFormat(), options: ImportOptions(correctWeekRollover: false))
        #expect(result.recording.trackPointCount == 5)
        #expect(result.warnings.isEmpty)
    }

    @Test func sonyLogFixture() throws {
        let url = try #require(Bundle.module.url(forResource: "sony-cs1", withExtension: "log", subdirectory: "Fixtures"))
        let input = try FileInput.load(url)
        #expect(FileFormats.detect(prefix: input.data, fileName: input.name)?.id == .nmea)
        let result = try FileFormats.readSynchronously([input], format: NMEAFileFormat(), options: ImportOptions(correctWeekRollover: false))
        #expect(result.recording.trackPointCount == 4)
        #expect(result.warnings.isEmpty)
    }

    @Test func csvIsNotNMEA() {
        let csv = Data("INDEX,TAG,DATE,TIME,LATITUDE N/S,LONGITUDE E/W,HEIGHT\n1,T,021126,120000,51.741157N,8.680967E,94\n".utf8)
        // A V-900 log: not NMEA, but its own format since change csv-logger-import.
        #expect(FileFormats.detect(prefix: csv, fileName: "track.csv")?.id == .v900)
        #expect(!NMEAFileFormat().matches(prefix: csv))
    }

    @Test func twoSentencesAreNotEnough() {
        let data = Data((rmc("120000") + "\n" + rmc("120001") + "\n").utf8)
        #expect(!NMEAFileFormat().matches(prefix: data))
    }
}
