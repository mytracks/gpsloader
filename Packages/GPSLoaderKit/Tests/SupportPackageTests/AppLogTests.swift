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

    /// Scenario "Rotation": a new file starts at the size limit, the oldest files are deleted.
    @Test func rotatesAndKeepsTheLimit() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = AppLog(directory: directory, maximumFileSize: 200, maximumFileCount: 3)
        for index in 0..<40 { log.log(.app, "entry \(index) " + String(repeating: "x", count: 40)) }
        let files = log.files
        #expect(files.map(\.lastPathComponent) == ["gpsloader.2.log", "gpsloader.1.log", "gpsloader.log"])
        let sizes = try files.map { try FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int ?? 0 }
        #expect(sizes.allSatisfy { $0 <= 200 })
        #expect(sizes.reduce(0, +) <= 3 * 200)
        let newest = try String(contentsOf: log.currentFile, encoding: .utf8)
        #expect(newest.contains("entry 39 "))
        let all = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined()
        #expect(!all.contains("entry 0 "))
    }
}
