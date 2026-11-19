import Foundation
import Testing
@testable import LoggerCore

/// Moving folders of builds named "gpsloader" (spec `support-package`, "App-Protokoll").
@Suite("Legacy folders")
struct LegacyFolderMigrationTests {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-\(UUID().uuidString)")

    private func folder(_ name: String, file: String? = nil) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if let file { try Data("old".utf8).write(to: url.appendingPathComponent(file)) }
        return url
    }

    /// Scenario "Ordner mit altem Namen".
    @Test func movesOldFolder() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try folder("gpsloader", file: "gpsloader.log")
        let new = root.appendingPathComponent("myTracks Loader", isDirectory: true)
        #expect(LegacyFolderMigration.migrate(from: old, to: new) == .moved)
        #expect(FileManager.default.fileExists(atPath: new.appendingPathComponent("gpsloader.log").path))
        #expect(!FileManager.default.fileExists(atPath: old.path))
    }

    /// Scenario "Beide Ordner vorhanden".
    @Test func keepsBoth() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try folder("gpsloader", file: "gpsloader.log")
        let new = try folder("myTracks Loader")
        #expect(LegacyFolderMigration.migrate(from: old, to: new) == .keptBoth)
        #expect(FileManager.default.fileExists(atPath: old.appendingPathComponent("gpsloader.log").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: new.path).isEmpty)
    }

    @Test func nothingToMove() {
        let old = root.appendingPathComponent("gpsloader")
        #expect(LegacyFolderMigration.migrate(from: old, to: root.appendingPathComponent("myTracks Loader")) == .nothingToMove)
    }

    @Test func names() {
        #expect(ProductName.name == "myTracks Loader")
        #expect(!ProductName.fileStem.contains(" "))
    }
}
