import Foundation
import Testing
@testable import GPSLoggerKit

/// Pads a V-900 field with NUL bytes to the given width, like the device does.
func v900Field(_ value: String, _ width: Int) -> String {
    value + String(repeating: "\0", count: max(0, width - value.count))
}

let v900SimpleHeader = "INDEX,TAG,DATE,TIME,LATITUDE N/S,LONGITUDE E/W,HEIGHT,SPEED,HEADING,VOX"
let v900ProHeader = "INDEX,TAG,DATE,TIME,LATITUDE N/S,LONGITUDE E/W,HEIGHT,SPEED,HEADING,FIX MODE,VALID,PDOP,HDOP,VDOP,VOX"

/// A simple-mode row with NUL padded fields.
func v900Row(_ index: Int, tag: String = "T", date: String = "261102", time: String = "120000",
             latitude: String = "50.000000N", longitude: String = "008.000000E", height: String = "100",
             speed: String = "36", heading: String = "45", vox: String = "") -> String {
    [v900Field(String(index), 6), tag, date, time, v900Field(latitude, 10), v900Field(longitude, 11),
     v900Field(height, 5), v900Field(speed, 4), v900Field(heading, 3), v900Field(vox, 9)].joined(separator: ",")
}

private func csv(_ name: String, _ lines: [String], ending: String = "\r\n") -> FileInput {
    FileInput(name: name, data: Data((lines.joined(separator: ending) + ending).utf8))
}

private func read(_ inputs: [FileInput], _ format: any FileFormat) throws -> ImportResult {
    try FileFormats.readSynchronously(inputs, format: format, options: ImportOptions(correctWeekRollover: false))
}

private func date(_ text: String) -> Date? { ISO8601.date(text) }

@Suite("CSV loggers – records")
struct CSVRecordsTests {
    private func records(_ text: String) -> [(Int, [String])] {
        var result: [(Int, [String])] = []
        CSVRecords.forEachRecord(in: Data(text.utf8)) { number, fields in
            result.append((number, fields.map(String.init)))
            return true
        }
        return result
    }

    /// Scenario "Felder mit Füllbytes".
    @Test func paddingIsTrimmed() {
        let result = records("a,100\0\0, b \t,\0\0\0\n")
        #expect(result.map(\.1) == [["a", "100", "b", ""]])
    }

    /// Scenario "Leere Zeile am Ende".
    @Test func emptyAndPaddingLinesAreSkipped() {
        let result = records("H\r\n1\r\n\r\n\0\0\0,\0\0\r\n")
        #expect(result.map(\.0) == [1, 2])
    }

    @Test(arguments: ["\n", "\r", "\r\n"])
    func lineEndings(ending: String) {
        let result = records(["H", "1", "2"].joined(separator: ending))
        #expect(result.map(\.0) == [1, 2, 3])
        #expect(result.map(\.1) == [["H"], ["1"], ["2"]])
    }

    @Test func byteOrderMarkIsRemoved() {
        let header = CSVRecords.header(in: Data("\u{FEFF}INDEX,date\r\n".utf8))
        #expect(header?.names == ["INDEX", "DATE"])
    }

    @Test func trailingCommaIsNoColumn() {
        #expect(CSVHeader(CSVRecords.fields(of: "A,B,")).names == ["A", "B"])
    }

    @Test func shortLineHasMissingFields() {
        let fields = CSVRecords.fields(of: "1,2")
        #expect(fields[field: 1] == "2")
        #expect(fields[field: 5] == nil)
        #expect(fields[field: nil] == nil)
        #expect(CSVRecords.fields(of: "1,,3")[field: 1] == nil)
    }
}

@Suite("CSV loggers – V-900")
struct V900Tests {
    /// Scenario "Einfacher Modus".
    @Test func simpleMode() throws {
        let result = try read([csv("26110201.CSV", [v900SimpleHeader, v900Row(1)])], V900FileFormat())
        let point = try #require(result.recording.tracks.first?.segments.first?.points.first)
        #expect(point.latitude == 50 && point.longitude == 8)
        #expect(point.time == date("2026-11-02T12:00:00Z"))
        #expect(point.elevation == 100)
        #expect(point.quality.speed == 10)
        #expect(point.quality.course == 45)
        #expect(point.quality.fix == nil)
        #expect(result.warnings.isEmpty)
        #expect(result.recording.waypoints.isEmpty)
    }

    /// Scenario from the spec text, with plain (unpadded) fields.
    @Test func unpaddedFields() throws {
        let result = try read([csv("a.csv", [v900SimpleHeader, "1,T,261102,120000,50.000000N,008.000000E,100,36,45,"])],
                              V900FileFormat())
        #expect(result.recording.trackPointCount == 1)
    }

    /// Scenario "Südlich und westlich".
    @Test func southAndWest() throws {
        let result = try read([csv("a.csv", [v900SimpleHeader, v900Row(1, latitude: "50.000200S", longitude: "008.000100W")])],
                              V900FileFormat())
        let point = try #require(result.recording.tracks.first?.segments.first?.points.first)
        #expect(point.latitude == -50.0002 && point.longitude == -8.0001)
    }

    /// Scenario "Professioneller Modus".
    @Test func professionalMode() throws {
        let row = [v900Field("1", 6), "T", "261102", "120000", v900Field("50.000000N", 10), v900Field("008.000000E", 11),
                   v900Field("100", 5), v900Field("5", 4), v900Field("45", 3), v900Field("3D", 4), v900Field("SPS", 5),
                   v900Field("2.1", 4), v900Field("1.2", 4), v900Field("1.8", 4), v900Field("", 9)].joined(separator: ",")
        let result = try read([csv("a.csv", [v900ProHeader, row])], V900FileFormat())
        let quality = try #require(result.recording.tracks.first?.segments.first?.points.first?.quality)
        #expect(quality.fix == .threeD)
        #expect(quality.pdop == 2.1 && quality.hdop == 1.2 && quality.vdop == 1.8)
    }

    /// Scenario "Differentielles GPS".
    @Test func differentialGPS() throws {
        let result = try read([csv("a.csv", [v900ProHeader, "1,T,261102,120000,50.0N,8.0E,100,5,45,2D,DGPS,0,0,0,"])],
                              V900FileFormat())
        let quality = try #require(result.recording.tracks.first?.segments.first?.points.first?.quality)
        #expect(quality.fix == .dgps)
        #expect(quality.pdop == nil)
    }

    @Test func twoDimensionalFix() throws {
        let result = try read([csv("a.csv", [v900ProHeader, "1,T,261102,120000,50.0N,8.0E,100,5,45,2D,SPS,1,1,1,"])],
                              V900FileFormat())
        #expect(result.recording.tracks.first?.segments.first?.points.first?.quality.fix == .twoD)
    }

    /// Scenario "Negative Höhe".
    @Test func negativeHeight() throws {
        let result = try read([csv("a.csv", [v900SimpleHeader, v900Row(1, height: "-5")])], V900FileFormat())
        #expect(result.recording.tracks.first?.segments.first?.points.first?.elevation == -5)
    }

    /// Scenario "Ungültige Hemisphäre".
    @Test func invalidHemisphere() throws {
        let result = try read([csv("a.csv", [v900SimpleHeader, v900Row(1), v900Row(2, latitude: "50.000000X")])],
                              V900FileFormat())
        #expect(result.recording.trackPointCount == 1)
        #expect(result.warnings == [ImportWarning(kind: .malformedRecord, count: 1, fileName: "a.csv", firstLine: 3)])
    }

    /// Scenario "Breite außerhalb des Bereichs".
    @Test func latitudeOutOfRange() throws {
        let result = try read([csv("a.csv", [v900SimpleHeader, v900Row(1), v900Row(2, latitude: "95.000000N")])],
                              V900FileFormat())
        #expect(result.recording.trackPointCount == 1)
        #expect(result.warnings == [ImportWarning(kind: .invalidCoordinate, count: 1, fileName: "a.csv", firstLine: 3)])
    }

    @Test func invalidDate() throws {
        let result = try read([csv("a.csv", [v900SimpleHeader, v900Row(1), v900Row(2, date: "261332"),
                                             v900Row(3, time: "246000")])], V900FileFormat())
        #expect(result.recording.trackPointCount == 1)
        #expect(result.warnings == [ImportWarning(kind: .malformedRecord, count: 2, fileName: "a.csv", firstLine: 3)])
    }

    /// Scenario "Unbrauchbare Zeile".
    @Test func shortRow() throws {
        let result = try read([csv("a.csv", [v900SimpleHeader, "1,T,261102", v900Row(2)])], V900FileFormat())
        #expect(result.recording.trackPointCount == 1)
        #expect(result.warnings == [ImportWarning(kind: .malformedRecord, count: 1, fileName: "a.csv", firstLine: 2)])
    }

    /// Scenarios "Markierung per Taste" and "Sprachaufnahme".
    @Test func markersBecomeWaypoints() throws {
        let rows = [v900SimpleHeader, v900Row(1), v900Row(2, tag: "C", time: "120001", latitude: "50.000100N"),
                    v900Row(3, tag: "V", time: "120002", vox: "VOX00003"), v900Row(4, tag: "D", time: "120003"),
                    v900Row(5, tag: "V", time: "120004"), v900Row(6, tag: "G", time: "120005")]
        let result = try read([csv("a.csv", rows)], V900FileFormat())
        #expect(result.recording.trackPointCount == 6)
        let waypoints = result.recording.waypoints
        #expect(waypoints.map(\.name) == ["POI 1", "VOX00003.WAV", "POI 3", "POI 4"])
        #expect(waypoints[0].latitude == 50.0001 && waypoints[0].longitude == 8)
        #expect(waypoints[0].time == date("2026-11-02T12:00:01Z"))
        #expect(waypoints[0].elevation == 100)
    }

    /// Scenario "Zwei Aufzeichnungen".
    @Test func oneTrackPerFile() throws {
        let result = try read([csv("26110201.CSV", [v900SimpleHeader, v900Row(1)]),
                               csv("26110202.CSV", [v900SimpleHeader, v900Row(1), v900Row(2)])], V900FileFormat())
        #expect(result.recording.tracks.map(\.name) == ["26110201", "26110202"])
        #expect(result.recording.tracks.map(\.pointCount) == [1, 2])
    }

    @Test func missingHeaderIsAnError() {
        #expect(throws: GPSLoggerError(.malformed(line: 1), fileName: "a.csv")) {
            try read([csv("a.csv", [v900Row(1)])], V900FileFormat())
        }
        #expect(throws: GPSLoggerError(.malformed(line: 1), fileName: "b.csv")) {
            try read([csv("b.csv", ["\0\0\0"])], V900FileFormat())
        }
    }

    @Test func headerWithoutRowsHasNoUsableData() {
        #expect(throws: GPSLoggerError(.noUsableData, fileName: "a.csv")) {
            try read([csv("a.csv", [v900SimpleHeader])], V900FileFormat())
        }
    }

    @Test func stopsSoonAfterCancellation() async throws {
        let row = v900Row(1) + "\r\n"
        let file = FileInput(name: "big.csv", data: Data((v900SimpleHeader + "\r\n" + String(repeating: row, count: 800_000)).utf8))
        #expect(file.data.count > 50_000_000)
        let task = Task { try await FileFormats.read([file], format: V900FileFormat()) }
        task.cancel()
        let start = Date()
        let result = await task.result
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(throws: CancellationError.self) { try result.get() }
    }
}

let iBlueHeader = "INDEX,RCR,DATE,TIME,VALID,LATITUDE,N/S,LONGITUDE,E/W,HEIGHT,SPEED,HEADING"

@Suite("CSV loggers – iBlue")
struct IBlueCSVTests {
    /// Scenario "Export eines iBlue 747".
    @Test func iBlue747Export() throws {
        let result = try read([csv("log.csv", [iBlueHeader, "1,T,2026/11/02,12:00:00,3d,50.000000,N,8.000000,E,100,5.4,45"])],
                              IBlueCSVFileFormat())
        let point = try #require(result.recording.tracks.first?.segments.first?.points.first)
        #expect(point.latitude == 50 && point.longitude == 8)
        #expect(point.time == date("2026-11-02T12:00:00Z"))
        #expect(point.elevation == 100)
        #expect(abs((point.quality.speed ?? 0) - 1.5) < 1e-9)
        #expect(point.quality.course == 45)
        #expect(point.quality.fix == .threeD)
        #expect(result.recording.tracks.map(\.name) == ["log"])
        #expect(result.warnings.isEmpty)
    }

    /// Scenario "Datum eines iBlue 757".
    @Test func iBlue757Date() throws {
        let result = try read([csv("a.csv", [iBlueHeader, "1,T,02/11/2026,12:00:00,3d,50.0,N,8.0,E,100,0,0"])],
                              IBlueCSVFileFormat())
        #expect(result.recording.tracks.first?.segments.first?.points.first?.time == date("2026-11-02T12:00:00Z"))
    }

    /// Scenario "Andere Spaltenreihenfolge".
    @Test func otherColumnOrder() throws {
        let result = try read([csv("a.csv", ["INDEX,DATE,TIME,LATITUDE,N/S,LONGITUDE,E/W,HEIGHT",
                                             "1,2026/11/02,12:00:00,50.5,S,8.5,E,321"])], IBlueCSVFileFormat())
        let point = try #require(result.recording.tracks.first?.segments.first?.points.first)
        #expect(point.latitude == -50.5 && point.longitude == 8.5 && point.elevation == 321)
        #expect(point.quality.isEmpty)
    }

    /// Scenario "Vorzeichen im Zahlenwert".
    @Test func signInValue() throws {
        let result = try read([csv("a.csv", [iBlueHeader, "1,T,2026/11/02,12:00:00,3d,50.0,N,-8.000456,W,100,0,0",
                                             "2,T,2026/11/02,12:00:01,3d,-50.0,N,8.0,E,100,0,0"])], IBlueCSVFileFormat())
        let points = try #require(result.recording.tracks.first?.segments.first?.points)
        #expect(points[0].longitude == -8.000456)
        #expect(points[1].latitude == 50)
    }

    /// Scenario "Satelliten".
    @Test func satellites() throws {
        let header = iBlueHeader + ",NSAT (USED/VIEW)"
        let result = try read([csv("a.csv", [header, "1,T,2026/11/02,12:00:00,3d,50.0,N,8.0,E,100,0,0,7(10)"])],
                              IBlueCSVFileFormat())
        #expect(result.recording.tracks.first?.segments.first?.points.first?.quality.satellites == 7)
    }

    /// Scenario "Unbekannte Werte".
    @Test func unknownValues() throws {
        let header = "INDEX,RCR,DATE,TIME,VALID,LATITUDE,N/S,LONGITUDE,E/W,HEIGHT,SPEED,HEADING,DSTA,DAGE,PDOP,HDOP,VDOP,NSAT (USED/VIEW),SAT INFO (SID-ELE-AZI-SNR),DISTANCE,"
        let row = "2,T,2026/11/02,12:00:01,Unknown,50.000123,N,-8.000456,W,101,9.0,,,,0.000000,0.000000,0.000000,-1(,,1142.718838"
        let result = try read([csv("a.csv", [header, row])], IBlueCSVFileFormat())
        let quality = try #require(result.recording.tracks.first?.segments.first?.points.first?.quality)
        #expect(quality.fix == nil && quality.pdop == nil && quality.hdop == nil && quality.vdop == nil)
        #expect(quality.satellites == nil && quality.course == nil)
        #expect(quality.speed == 2.5)
    }

    @Test(arguments: [("2d", FixType.twoD), ("3D", .threeD), ("DGPS", .dgps), ("No Fix", nil), ("SPS", nil)])
    func fixTypes(value: String, expected: FixType?) throws {
        let result = try read([csv("a.csv", [iBlueHeader, "1,T,2026/11/02,12:00:00,\(value),50.0,N,8.0,E,100,0,0"])],
                              IBlueCSVFileFormat())
        #expect(result.recording.tracks.first?.segments.first?.points.first?.quality.fix == expected)
    }

    /// Scenario "Millisekunden".
    @Test func milliseconds() throws {
        let result = try read([csv("a.csv", [iBlueHeader, "1,T,2026/11/02,12:00:00.500,3d,50.0,N,8.0,E,100,0,0"])],
                              IBlueCSVFileFormat())
        #expect(result.recording.tracks.first?.segments.first?.points.first?.time == date("2026-11-02T12:00:00.500Z"))
    }

    /// Scenario "Pflichtspalte fehlt".
    @Test func missingRequiredColumn() {
        #expect(throws: GPSLoggerError(.malformed(line: 1), fileName: "a.csv")) {
            try read([csv("a.csv", ["INDEX,DATE,TIME,LATITUDE,N/S,LONGITUDE", "1,2026/11/02,12:00:00,50,N,8"])],
                     IBlueCSVFileFormat())
        }
    }

    @Test func malformedRows() throws {
        let rows = [iBlueHeader, "1,T,2026-11-02,12:00:00,3d,50.0,N,8.0,E,100,0,0",
                    "2,T,2026/11/02,12:00:00,3d,50.0,X,8.0,E,100,0,0",
                    "3,T,26/11/02,12:00:00,3d,50.0,N,8.0,E,100,0,0",
                    "4,T,2026/11/02,12:00,3d,50.0,N,8.0,E,100,0,0",
                    "5,T,2026/11/02,12:00:00,3d,abc,N,8.0,E,100,0,0",
                    "6,T,2026/11/02,12:00:00,3d,50.0,N,181.0,E,100,0,0",
                    "7,T,2026/11/02,12:00:00,3d,50.0,N,8.0,E,100,0,0"]
        let result = try read([csv("a.csv", rows)], IBlueCSVFileFormat())
        #expect(result.recording.trackPointCount == 1)
        #expect(result.warnings == [ImportWarning(kind: .malformedRecord, count: 5, fileName: "a.csv", firstLine: 2),
                                    ImportWarning(kind: .invalidCoordinate, count: 1, fileName: "a.csv", firstLine: 7)])
    }

    @Test func stopsSoonAfterCancellation() async throws {
        let row = "1,T,2026/11/02,12:00:00,3d,50.000000,N,8.000000,E,100,5.4,45\r\n"
        let file = FileInput(name: "big.csv", data: Data((iBlueHeader + "\r\n" + String(repeating: row, count: 900_000)).utf8))
        #expect(file.data.count > 50_000_000)
        let task = Task { try await FileFormats.read([file], format: IBlueCSVFileFormat()) }
        task.cancel()
        let start = Date()
        let result = await task.result
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(throws: CancellationError.self) { try result.get() }
    }
}

@Suite("CSV loggers – detection")
struct CSVDetectionTests {
    /// Scenario "V-900-Datei mit Endung .CSV".
    @Test func v900() {
        let data = Data((v900SimpleHeader + "\r\n" + v900Row(1) + "\r\n").utf8)
        #expect(FileFormats.detect(prefix: data, fileName: "26110201.CSV")?.id == .v900)
        #expect(FileFormats.detect(prefix: data, fileName: "track.txt")?.id == .v900)
        #expect(!IBlueCSVFileFormat().matches(prefix: data))
        let pro = Data((v900ProHeader + "\r\n").utf8)
        #expect(FileFormats.detect(prefix: pro, fileName: "a.csv")?.id == .v900)
    }

    /// Scenario "iBlue-Datei".
    @Test func iBlue() {
        let data = Data((iBlueHeader + "\r\n1,T,2026/11/02,12:00:00,3d,50.0,N,8.0,E,100,0,0\r\n").utf8)
        #expect(FileFormats.detect(prefix: data, fileName: "log.csv")?.id == .iblueCSV)
        #expect(!V900FileFormat().matches(prefix: data))
    }

    /// Scenario "Fremde CSV-Datei".
    @Test func otherCSV() {
        #expect(FileFormats.detect(prefix: Data("Name,Vorname,Ort\r\nMuster,Max,Stadt\r\n".utf8), fileName: "a.csv") == nil)
        #expect(FileFormats.detect(prefix: Data("INDEX,DATE,TIME\r\n".utf8), fileName: "a.csv") == nil)
    }

    @Test func otherFormatsDoNotMatch() {
        let samples = [
            "$GPRMC,120000,A,5000.000,N,00800.000,E,0.0,0.0,021126,,*15\r\n",
            "<?xml version=\"1.0\"?><gpx version=\"1.1\"></gpx>",
            "AXXX001\r\nHFDTE021126\r\nB1200005000000N00800000EA0010000100\r\n",
        ]
        for sample in samples {
            #expect(!V900FileFormat().matches(prefix: Data(sample.utf8)))
            #expect(!IBlueCSVFileFormat().matches(prefix: Data(sample.utf8)))
        }
    }
}
