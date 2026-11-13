import Foundation
import Testing
@testable import GPSLoggerKit

/// A format that recognizes files starting with `TESTFORMAT` and reads one waypoint.
struct CatalogTestFormat: FileFormat {
    var id: FileFormatID = "test-format"
    var displayName: String { "Test format" }
    var fileExtensions: [String] { ["tst"] }

    func matches(prefix: Data) -> Bool {
        prefix.starts(with: Data("TESTFORMAT".utf8))
    }

    func read(_ inputs: [FileInput]) throws -> ImportResult {
        var recording = Recording()
        recording.waypoints = inputs.map { Waypoint(latitude: 50, longitude: 8, name: $0.name) }
        return ImportResult(recording: recording)
    }
}

@Suite("Format catalog")
struct FormatCatalogTests {
    /// Spec `logger-kit`, "Standardkatalog unverändert".
    @Test func standardCatalogIsThePackageCatalog() {
        #expect(FormatCatalog.standard.all.map(\.id) == FileFormats.all.map(\.id))
        #expect(FileFormats.detect(prefix: Data("TESTFORMAT".utf8), fileName: "a.tst") == nil)
    }

    /// Spec `logger-kit`, "Zusätzliches Format erkennen".
    @Test func additionalFormatIsDetected() throws {
        let catalog = FormatCatalog.standard.adding([CatalogTestFormat()])
        let format = try #require(catalog.detect(prefix: Data("TESTFORMAT 1\n".utf8), fileName: "a.tst"))
        #expect(format.id == "test-format")
        #expect(catalog.format(withID: "test-format") != nil)
        let nmea = Data(String(repeating: "$GPRMC,120000,A,5000.000,N,00800.000,E,0.0,0.0,021126,,*15\n", count: 3).utf8)
        #expect(catalog.detect(prefix: nmea, fileName: "a.tst")?.id == .nmea)
    }

    @Test func ownFormatsComeFirst() {
        let catalog = FormatCatalog.standard.adding([CatalogTestFormat()])
        #expect(catalog.all.map(\.id) == FileFormats.all.map(\.id) + ["test-format"])
    }

    @Test func additionalFormatIsRead() throws {
        let catalog = FormatCatalog.standard.adding([CatalogTestFormat()])
        let input = FileInput(name: "a.tst", data: Data("TESTFORMAT\n".utf8))
        let format = try #require(catalog.detect(prefix: input.data, fileName: input.name))
        let result = try FileFormats.readSynchronously([input], format: format)
        #expect(result.recording.waypoints.map(\.name) == ["a.tst"])
    }

    @Test func duplicateIdentifiersAreFound() {
        #expect(FormatCatalog.duplicateIDs(in: FileFormats.all).isEmpty)
        let formats: [any FileFormat] = FileFormats.all + [CatalogTestFormat(id: .gpx), CatalogTestFormat(), CatalogTestFormat()]
        #expect(FormatCatalog.duplicateIDs(in: formats) == [.gpx, "test-format"])
    }
}
