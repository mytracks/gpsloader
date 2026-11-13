// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import GPSLoggerKit
@testable import GPSLoggerKitGPL

/// Reference date of the tests: 2026-11-13, so that week 380 lies in the current cycle (absolute week 2428).
let skyTraqReference = Date(timeIntervalSince1970: 1_794_528_000)

private func read(_ dumps: [(String, Data)]) throws -> ImportResult {
    try FileFormats.readSynchronously(dumps.map { FileInput(name: $0.0, data: $0.1) },
                                      format: SkyTraqBinFileFormat(reference: skyTraqReference),
                                      options: ImportOptions(correctWeekRollover: true, referenceDate: skyTraqReference))
}

private func read(_ dump: SkyTraqTestDump, name: String = "venus.bin") throws -> ImportResult {
    try read([(name, dump.data)])
}

private func date(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

@Suite("GPSLoggerKitGPL support")
struct ImportSupportTests {
    /// Scenario "Aktueller Wochenzyklus".
    @Test func currentWeekCycle() {
        let week = GPSTime.absoluteWeek(tenBit: 380, reference: skyTraqReference)
        #expect(week == 2428)
        #expect(GPSTime.date(absoluteWeek: week, secondOfWeek: 302_400) == date("2026-07-22T11:59:42Z"))
    }

    @Test func weekAboveCurrentBelongsToThePreviousCycle() {
        // 2026-11-13 is in absolute week 2444, i.e. week 396 of the third cycle.
        #expect(GPSTime.absoluteWeek(tenBit: 396, reference: skyTraqReference) == 2444)
        #expect(GPSTime.absoluteWeek(tenBit: 397, reference: skyTraqReference) == 1421)
    }

    @Test func leapSecondsAtTheEndOf2016() {
        // GPS 2017-01-01T00:00:17 is UTC 2016-12-31T23:59:60 → reported as 23:59:59 + 1 s with 17 s offset;
        // from GPS 00:00:18 on the offset is 18 s.
        let start2017 = 1_483_228_800.0
        #expect(GPSTime.offset(gpsSeconds: start2017 + 18) == 18)
        #expect(GPSTime.offset(gpsSeconds: start2017 + 16) == 17)
        #expect(GPSTime.offset(gpsSeconds: 1_000_000_000) == 13)
    }

    @Test func warningsAreSummarized() {
        var warnings = Warnings(fileName: "a.bin")
        warnings.add(.malformedRecord, at: 3)
        warnings.add(.malformedRecord, at: 9)
        warnings.add(.truncatedFile, at: nil)
        #expect(warnings.all == [ImportWarning(kind: .malformedRecord, count: 2, fileName: "a.bin", firstLine: 3),
                                 ImportWarning(kind: .truncatedFile, count: 1, fileName: "a.bin")])
    }

    @Test func byteReaderIsBoundsChecked() {
        let reader = ByteReader(bytes: [0x12, 0x34, 0x56])
        #expect(reader.u16be(0) == 0x1234 && reader.u16le(1) == 0x5634)
        #expect(reader.u16be(2) == nil && reader.u32le(0) == nil && reader.u8(3) == nil && reader.u8(-1) == nil)
        #expect(ByteReader(bytes: [1, 2, 3, 4]).u32le(0) == 0x0403_0201)
        #expect(ByteReader(bytes: [1, 2, 3, 4]).u32be(0) == 0x0102_0304)
    }

    @Test(arguments: ["de", "en"])
    func formatNamesAreLocalized(localization: String) {
        let name = L10n.string("format.skytraq-bin", localization: localization)
        #expect(name == (localization == "de" ? "SkyTraq-Speicherabbild" : "SkyTraq memory dump"))
    }

    @Test func trackNameIsTheFileName() {
        #expect(trackName(ofFile: "/a/b/venus.bin") == "venus")
        #expect(trackName(ofFile: ".bin") == ".bin")
    }
}

@Suite("SkyTraq dumps")
struct SkyTraqTests {
    /// Scenario "Position aus ECEF" and "Zeit eines vollen Eintrags".
    @Test func fullItem() throws {
        var dump = SkyTraqTestDump()
        dump.append(SkyTraqTestDump.full(week: 380, second: 302_400, latitude: 50, longitude: 8, height: 100, speed: 36))
        dump.endSector()
        let result = try read(dump)
        let point = try #require(result.recording.tracks.first?.segments.first?.points.first)
        #expect(abs(point.latitude - 50) < 0.00001 && abs(point.longitude - 8) < 0.00001)
        #expect(abs((point.elevation ?? 0) - 100) < 1)
        #expect(point.time == date("2026-07-22T11:59:42Z"))
        #expect(point.quality.speed == 10)
        #expect(result.warnings.isEmpty)
    }

    @Test func middleEndianMatchesTheEncoder() {
        let bytes = SkyTraqTestDump.middleEndian(UInt32(0x1234_5678))
        #expect(bytes == [0x56, 0x78, 0x12, 0x34])
        #expect(SkyTraqDump.middleEndian32(ByteReader(bytes: bytes), 0) == 0x1234_5678)
    }

    /// Scenario "Fortgeschriebene Position".
    @Test func compactItemContinuesFromTheFullOne() throws {
        let (x, y, z) = SkyTraqTestDump.ecef(latitude: 50, longitude: 8, height: 100)
        var dump = SkyTraqTestDump()
        dump.append(SkyTraqTestDump.full(week: 380, second: 302_400, x: x, y: y, z: z))
        dump.append(SkyTraqTestDump.compact(dt: 5, dx: 3, dy: -2, dz: 1))
        dump.endSector()
        let points = try #require(try read(dump).recording.tracks.first?.segments.first?.points)
        #expect(points.count == 2)
        #expect(points[1].time == points[0].time.map { $0.addingTimeInterval(5) })
        let expected = SkyTraqDump.geodetic(x: Double(x + 3), y: Double(y - 2), z: Double(z + 1))
        #expect(points[1].latitude == expected.0 && points[1].longitude == expected.1 && points[1].elevation == expected.2)
    }

    @Test func negativeDeltas() {
        #expect(SkyTraqDump.signed10(512) == -1)
        #expect(SkyTraqDump.signed10(1023) == -512)
        #expect(SkyTraqDump.signed10(511) == 511)
        for d in [-512, -1, 0, 1, 511] {
            #expect(SkyTraqDump.signed10(SkyTraqTestDump.delta10(d)) == d)
        }
    }

    /// Scenario "Zehn Punkte pro Sekunde".
    @Test func multiHzKeepsMilliseconds() throws {
        var dump = SkyTraqTestDump()
        dump.append(SkyTraqTestDump.multiHz(week: 380, millisecond: 302_400_000, latitude: 50, longitude: 8, height: 100.5, speed: 36))
        dump.append(SkyTraqTestDump.multiHz(week: 380, millisecond: 302_400_100, latitude: -50, longitude: -8, height: -2))
        dump.endSector()
        let points = try #require(try read(dump).recording.tracks.first?.segments.first?.points)
        #expect(points.count == 2)
        let interval = try #require(points[1].time).timeIntervalSince(try #require(points[0].time))
        #expect(abs(interval - 0.1) < 0.0005)
        #expect(points[0].latitude == 50 && points[0].longitude == 8 && points[0].elevation == 100.5)
        #expect(points[1].latitude == -50 && points[1].longitude == -8 && points[1].elevation == -2)
        #expect(points[0].quality.speed == 10)
    }

    /// Scenario "Taste gedrückt", plus a POI item at high rate.
    @Test func poiItemsBecomeWaypoints() throws {
        var dump = SkyTraqTestDump()
        dump.append(SkyTraqTestDump.full(week: 380, second: 1, latitude: 50, longitude: 8, height: 100))
        dump.append(SkyTraqTestDump.full(week: 380, second: 2, latitude: 50.001, longitude: 8, height: 100))
        dump.append(SkyTraqTestDump.full(week: 380, second: 3, latitude: 50.002, longitude: 8, height: 100, poi: true))
        dump.append(SkyTraqTestDump.multiHz(week: 380, millisecond: 4000, latitude: 50.003, longitude: 8, height: 100, poi: true))
        dump.endSector()
        let result = try read(dump)
        let points = try #require(result.recording.tracks.first?.segments.first?.points)
        #expect(points.count == 4)
        #expect(result.recording.waypoints.map(\.name) == ["POI 1", "POI 2"])
        #expect(result.recording.waypoints[0].latitude == points[2].latitude)
        #expect(result.recording.waypoints[0].time == points[2].time)
        #expect(abs(result.recording.waypoints[1].latitude - 50.003) < 1e-6)
    }

    /// Scenario "Leerer Sektor beendet das Abbild".
    @Test func emptySectorEndsTheDump() throws {
        var dump = SkyTraqTestDump()
        dump.append(SkyTraqTestDump.full(week: 380, second: 1, latitude: 50, longitude: 8, height: 100))
        dump.endSector()
        dump.endSector()
        dump.append(SkyTraqTestDump.full(week: 380, second: 9, latitude: 10, longitude: 10, height: 0))
        dump.endSector()
        let result = try read(dump)
        #expect(result.recording.trackPointCount == 1)
        #expect(result.warnings.isEmpty)
    }

    /// Scenario "Voller Sektor": a sector used up to less than 18 bytes before its end is followed.
    @Test func fullSectorIsFollowed() throws {
        let result = try read(SkyTraqTestDump.venus())
        #expect(result.recording.trackPointCount == 509 + 7)
    }

    @Test func shortLastSectorIsRead() throws {
        let item = SkyTraqTestDump.full(week: 380, second: 1, latitude: 50, longitude: 8, height: 100)
        let result = try read([("a.bin", Data(item))])
        #expect(result.recording.trackPointCount == 1)
    }

    /// Scenario "Unbekannter Eintrag".
    @Test func unknownItemTruncatesTheDump() throws {
        var dump = SkyTraqTestDump()
        for second in 1...3 {
            dump.append(SkyTraqTestDump.full(week: 380, second: second, latitude: 50, longitude: 8, height: 100))
        }
        dump.append([0x10, 0x00, 0x00])
        dump.endSector()
        let result = try read(dump)
        #expect(result.recording.trackPointCount == 3)
        #expect(result.warnings.map(\.kind) == [.truncatedFile])
    }

    @Test func itemCrossingTheSectorEndTruncatesTheDump() throws {
        var bytes = SkyTraqTestDump.full(week: 380, second: 1, latitude: 50, longitude: 8, height: 100)
        for _ in 0..<509 { bytes += SkyTraqTestDump.compact(dt: 1, dx: 1, dy: 1, dz: 1) }
        bytes += SkyTraqTestDump.full(week: 380, second: 2, latitude: 50, longitude: 8, height: 100).prefix(6)
        #expect(bytes.count == 4096)
        let result = try read([("a.bin", Data(bytes))])
        #expect(result.recording.trackPointCount == 510)
        #expect(result.warnings.map(\.kind) == [.truncatedFile])
    }

    /// Scenario "Komprimierter Eintrag am Anfang".
    @Test func compactItemWithoutPosition() throws {
        var dump = SkyTraqTestDump()
        dump.append(SkyTraqTestDump.compact(dt: 1, dx: 1, dy: 1, dz: 1))
        dump.append(SkyTraqTestDump.full(week: 380, second: 1, latitude: 50, longitude: 8, height: 100))
        dump.endSector()
        let result = try read(dump)
        #expect(result.recording.trackPointCount == 1)
        #expect(result.warnings.map(\.kind) == [.malformedRecord])
    }

    /// Scenario "Abbild aus gpsbabel" and one track per dump.
    @Test func oneTrackPerDump() throws {
        let one = SkyTraqTestDump.full(week: 380, second: 1, latitude: 50, longitude: 8, height: 100)
        let result = try read([("venus.bin", Data(one)), ("second.bin", Data(one + one))])
        #expect(result.recording.tracks.map(\.name) == ["venus", "second"])
        #expect(result.recording.tracks.map(\.pointCount) == [1, 2])
    }

    @Test func emptyDumpHasNoUsableData() {
        #expect(throws: GPSLoggerError(.noUsableData, fileName: "a.bin")) {
            try read([("a.bin", Data(repeating: 0xFF, count: 4096))])
        }
    }

    @Test func stopsSoonAfterCancellation() async throws {
        var dump = SkyTraqTestDump()
        dump.append(SkyTraqTestDump.full(week: 380, second: 1, latitude: 50, longitude: 8, height: 100))
        for _ in 0..<508 { dump.append(SkyTraqTestDump.compact(dt: 1, dx: 1, dy: 0, dz: 0)) }
        dump.endSector()
        let sector = dump.bytes
        let file = FileInput(name: "big.bin", data: Data((0..<13_000).flatMap { _ in sector }))
        #expect(file.data.count > 50_000_000)
        let task = Task { try await FileFormats.read([file], format: SkyTraqBinFileFormat(reference: skyTraqReference)) }
        task.cancel()
        let start = Date()
        let result = await task.result
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(throws: CancellationError.self) { try result.get() }
    }
}

@Suite("SkyTraq detection")
struct SkyTraqDetectionTests {
    private let catalog = FormatCatalog.standard.adding(GPLFileFormats.all)

    /// Scenario "Abbild mit Endung .bin".
    @Test func dumpIsDetected() {
        let prefix = SkyTraqTestDump.venus().data.prefix(4096)
        #expect(catalog.detect(prefix: Data(prefix), fileName: "log.bin")?.id == .skytraqBin)
        #expect(catalog.detect(prefix: Data(prefix), fileName: "log.dat")?.id == .skytraqBin)
    }

    @Test func multiHzStartIsDetected() {
        var dump = SkyTraqTestDump()
        dump.append(SkyTraqTestDump.multiHz(week: 380, millisecond: 1000, latitude: 50, longitude: 8, height: 100))
        dump.endSector()
        #expect(SkyTraqBinFileFormat().matches(prefix: dump.data))
    }

    /// Scenario "Andere Binärdatei".
    @Test func otherBinaryFilesAreNotDetected() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<50 {
            let random = Data((0..<4096).map { _ in UInt8.random(in: 0...255, using: &generator) })
            #expect(!SkyTraqBinFileFormat().matches(prefix: random))
        }
        let fitHeader = Data([14, 0x10, 0x00, 0x00, 0, 0, 0, 0] + Array(".FIT".utf8) + [0, 0])
        #expect(!SkyTraqBinFileFormat().matches(prefix: fitHeader))
        #expect(!SkyTraqBinFileFormat().matches(prefix: Data(repeating: 0xFF, count: 4096)))
        #expect(!SkyTraqBinFileFormat().matches(prefix: Data("$GPRMC,120000,A,5000.000,N".utf8)))
        var compactFirst = SkyTraqTestDump()
        compactFirst.append(SkyTraqTestDump.compact(dt: 1, dx: 1, dy: 1, dz: 1))
        compactFirst.endSector()
        #expect(!SkyTraqBinFileFormat().matches(prefix: compactFirst.data))
        var farAway = SkyTraqTestDump()
        farAway.append(SkyTraqTestDump.full(week: 1, second: 1, x: 1000, y: 1000, z: 1000))
        farAway.endSector()
        #expect(!SkyTraqBinFileFormat().matches(prefix: farAway.data))
    }
}
