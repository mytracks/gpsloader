import Foundation
import Testing
@testable import GPSLoggerKit

/// A small KML document with one path of three points.
func pathKML(name: String = "Runde") -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <kml xmlns="http://www.opengis.net/kml/2.2"><Document><Placemark><name>\(name)</name>
    <LineString><coordinates>8,50,100 8.001,50.001,101 8.002,50.002,102</coordinates></LineString>
    </Placemark></Document></kml>
    """
}

private let image = [UInt8](repeating: 0xFF, count: 300) + [0xD8, 0xFF, 0xE0]

private func readKMZ(_ archive: KMZTestFile, name: String = "tour.kmz") throws -> ImportResult {
    try KMLFileFormat().read([FileInput(name: name, data: Data(archive.bytes()))])
}

private func failsNamingTheFile(_ archive: KMZTestFile, _ kind: (GPSLoggerErrorKind) -> Bool) -> Bool {
    do {
        _ = try readKMZ(archive)
        return false
    } catch let error as GPSLoggerError {
        return error.fileName == "tour.kmz" && kind(error.kind)
    } catch {
        return false
    }
}

@Suite("KMZ archives")
struct KMZTests {
    @Test func crc32CheckValue() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(CRC32.checksum(Data()) == 0)
    }

    #if os(macOS)
    /// The test encoder writes archives that `unzip` accepts.
    @Test func encoderOutputPassesUnzip() throws {
        var archive = KMZTestFile()
        archive.entries = [KMZTestFile.Entry("doc.kml", pathKML()), KMZTestFile.Entry("files/a.jpg", bytes: image, method: 0)]
        var described = KMZTestFile.Entry("other.kml", pathKML())
        described.dataDescriptor = true
        archive.entries.append(described)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kmz-\(UUID().uuidString).zip")
        try Data(archive.bytes()).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-tq", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
    #endif

    /// Scenario "Archiv mit Bildern".
    @Test func archiveWithImages() throws {
        var archive = KMZTestFile()
        archive.entries = [
            KMZTestFile.Entry("doc.kml", pathKML()),
            KMZTestFile.Entry("files/a.jpg", bytes: image), KMZTestFile.Entry("files/b.jpg", bytes: image, method: 0),
        ]
        let result = try readKMZ(archive)
        #expect(result.recording.tracks.map(\.name) == ["Runde"])
        #expect(result.recording.trackPointCount == 3)
        #expect(result.warnings.map(\.kind) == [.missingTimes])
    }

    /// Scenario "Anderer Dateiname"; `doc.kml` in a subfolder does not count.
    @Test func otherDocumentName() throws {
        var archive = KMZTestFile()
        archive.entries = [KMZTestFile.Entry("tour.kml", pathKML(name: "Tour"))]
        #expect(try readKMZ(archive).recording.tracks.map(\.name) == ["Tour"])

        archive.entries = [KMZTestFile.Entry("sub/doc.kml", pathKML(name: "Unten")), KMZTestFile.Entry("tour.kml", pathKML(name: "Tour"))]
        #expect(try readKMZ(archive).recording.tracks.map(\.name) == ["Tour"])

        archive.entries = [KMZTestFile.Entry("a.kml", pathKML(name: "A")), KMZTestFile.Entry("DOC.KML", pathKML(name: "Doc"))]
        #expect(try readKMZ(archive).recording.tracks.map(\.name) == ["Doc"])
    }

    @Test func storedDeflatedAndDataDescriptor() throws {
        for method: UInt16 in [0, 8] {
            for descriptor in [false, true] {
                var entry = KMZTestFile.Entry("doc.kml", pathKML(), method: method)
                entry.dataDescriptor = descriptor
                let result = try readKMZ(KMZTestFile(entries: [entry]))
                #expect(result.recording.trackPointCount == 3, "method \(method), descriptor \(descriptor)")
            }
        }
    }

    /// Scenario "Falsche Prüfsumme".
    @Test func wrongChecksumIsAWarning() throws {
        var entry = KMZTestFile.Entry("doc.kml", pathKML())
        entry.wrongCRC = true
        let result = try readKMZ(KMZTestFile(entries: [entry]))
        #expect(result.recording.trackPointCount == 3)
        #expect(result.warnings.contains(ImportWarning(kind: .fileChecksumMismatch, count: 1, fileName: "tour.kmz")))
    }

    /// Scenario "Kein KML im Archiv".
    @Test func archiveWithoutKML() {
        let archive = KMZTestFile(entries: [KMZTestFile.Entry("files/a.jpg", bytes: image)])
        #expect(failsNamingTheFile(archive) { $0 == .noUsableData })
    }

    /// Scenario "Abgeschnittenes Archiv".
    @Test func truncatedArchive() throws {
        let bytes = KMZTestFile(entries: [KMZTestFile.Entry("doc.kml", pathKML())]).bytes()
        let half = Data(bytes.prefix(bytes.count / 2))
        #expect {
            try KMLFileFormat().read([FileInput(name: "tour.kmz", data: half)])
        } throws: { error in
            guard let error = error as? GPSLoggerError, case .malformed = error.kind else { return false }
            return error.fileName == "tour.kmz"
        }
    }

    @Test func unsupportedArchivesAreErrors() {
        var encrypted = KMZTestFile.Entry("doc.kml", pathKML())
        encrypted.encrypted = true
        #expect(failsNamingTheFile(KMZTestFile(entries: [encrypted])) { $0 == .unreadable })

        var zip64 = KMZTestFile.Entry("doc.kml", pathKML())
        zip64.zip64Sizes = true
        #expect(failsNamingTheFile(KMZTestFile(entries: [zip64])) { $0 == .unreadable })

        let bzip2 = KMZTestFile.Entry("doc.kml", pathKML(), method: 12)
        #expect(failsNamingTheFile(KMZTestFile(entries: [bzip2])) { $0 == .unreadable })

        var huge = KMZTestFile.Entry("doc.kml", pathKML())
        huge.declaredSize = UInt32(KMZArchive.maximumDocumentSize) + 1
        #expect(failsNamingTheFile(KMZTestFile(entries: [huge])) { $0 == .unreadable })
    }

    /// The deflate stream yields more (or less) than the declared size.
    @Test func sizeMismatchIsAnError() {
        var tooSmall = KMZTestFile.Entry("doc.kml", pathKML())
        tooSmall.declaredSize = 20
        #expect(failsNamingTheFile(KMZTestFile(entries: [tooSmall])) { if case .malformed = $0 { true } else { false } })

        var tooLarge = KMZTestFile.Entry("doc.kml", pathKML())
        tooLarge.declaredSize = UInt32(pathKML().utf8.count + 10)
        #expect(failsNamingTheFile(KMZTestFile(entries: [tooLarge])) { if case .malformed = $0 { true } else { false } })
    }

    @Test func damagedDeflateDataIsAnError() {
        var bytes = KMZTestFile(entries: [KMZTestFile.Entry("doc.kml", pathKML())]).bytes()
        // Cut the deflate stream in the middle but keep the archive structure: shorten the stored payload.
        let nameLength = "doc.kml".utf8.count
        let payloadStart = 30 + nameLength
        let payloadSize = Int(bytes[18]) | Int(bytes[19]) << 8
        let cut = payloadSize / 2
        bytes.removeSubrange((payloadStart + cut)..<(payloadStart + payloadSize))
        // Patch the compressed size in local and central header and the central directory offset.
        func put32(_ value: Int, at offset: Int) {
            for i in 0..<4 { bytes[offset + i] = UInt8((value >> (8 * i)) & 0xFF) }
        }
        put32(cut, at: 18)
        let centralStart = payloadStart + cut
        put32(cut, at: centralStart + 20)
        put32(centralStart, at: bytes.count - 6)
        #expect {
            try KMLFileFormat().read([FileInput(name: "tour.kmz", data: Data(bytes))])
        } throws: { error in
            guard let error = error as? GPSLoggerError, case .malformed = error.kind else { return false }
            return error.fileName == "tour.kmz"
        }
    }

    @Test func largeArchiveStopsSoonAfterCancellation() async throws {
        let tuples = String(repeating: "8.000001,50.000001,100 ", count: 2_300_000)
        let document = "<kml><Placemark><LineString><coordinates>\(tuples)</coordinates></LineString></Placemark></kml>"
        #expect(document.utf8.count > 50_000_000)
        let archive = KMZTestFile(entries: [KMZTestFile.Entry("doc.kml", document)])
        let big = FileInput(name: "big.kmz", data: Data(archive.bytes()))
        let task = Task { try await FileFormats.read([big], format: KMLFileFormat()) }
        task.cancel()
        let start = Date()
        let result = await task.result
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(throws: CancellationError.self) { try result.get() }
    }
}
