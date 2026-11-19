import Foundation
import Testing
@testable import SupportPackage

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("applog-\(UUID().uuidString)", isDirectory: true)
}

@Suite("App log")
struct AppLogTests {
    @Test func writesLinesWithTimeAndCategory() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = AppLog(directory: directory, now: { Date(timeIntervalSince1970: 1_793_700_000) })
        log.log(.operation, "read mtk /dev/cu.usbserial-1410: protocol error\nUnexpected answer")
        let text = try String(contentsOf: log.currentFile, encoding: .utf8)
        #expect(text.hasSuffix("[operation] read mtk /dev/cu.usbserial-1410: protocol error Unexpected answer\n"))
        #expect(text.split(separator: "\n").count == 1)
        #expect(text.hasPrefix("2026-11-"))
    }

    /// Scenario "Ordner mit altem Namen": files of earlier builds become the oldest files under the new name.
    @Test func adoptsLegacyFiles() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, text) in [("gpsloader.log", "old 0"), ("gpsloader.1.log", "old 1"), ("myTracks Loader.log", "new 0")] {
            try Data(text.utf8).write(to: directory.appendingPathComponent(name))
        }
        let log = AppLog(directory: directory, maximumFileCount: 3)
        log.adoptLegacyFiles()
        #expect(log.files.map(\.lastPathComponent) == ["myTracks Loader.2.log", "myTracks Loader.1.log", "myTracks Loader.log"])
        #expect(try String(contentsOf: log.files[0], encoding: .utf8) == "old 1")
        #expect(try String(contentsOf: log.files[1], encoding: .utf8) == "old 0")
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("gpsloader.log").path))
    }

    /// Legacy files beyond the file limit are removed, as rotation would.
    @Test func adoptsLegacyFilesWithinTheLimit() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["gpsloader.log", "gpsloader.1.log", "myTracks Loader.log", "myTracks Loader.1.log"] {
            try Data("x".utf8).write(to: directory.appendingPathComponent(name))
        }
        let log = AppLog(directory: directory, maximumFileCount: 3)
        log.adoptLegacyFiles()
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(names == ["myTracks Loader.1.log", "myTracks Loader.2.log", "myTracks Loader.log"])
    }

    /// Scenario "Rotation": a new file starts at the size limit, the oldest files are deleted.
    @Test func rotatesAndKeepsTheLimit() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = AppLog(directory: directory, maximumFileSize: 200, maximumFileCount: 3)
        for index in 0..<40 { log.log(.app, "entry \(index) " + String(repeating: "x", count: 40)) }
        let files = log.files
        #expect(files.map(\.lastPathComponent) == ["myTracks Loader.2.log", "myTracks Loader.1.log", "myTracks Loader.log"])
        let sizes = try files.map { try FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int ?? 0 }
        #expect(sizes.allSatisfy { $0 <= 200 })
        #expect(sizes.reduce(0, +) <= 3 * 200)
        let newest = try String(contentsOf: log.currentFile, encoding: .utf8)
        #expect(newest.contains("entry 39 "))
        let all = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined()
        #expect(!all.contains("entry 0 "))
    }
}
