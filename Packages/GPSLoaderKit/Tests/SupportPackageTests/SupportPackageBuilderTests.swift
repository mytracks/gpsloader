import Foundation
import Testing
@testable import SupportPackage

/// File names in the central directory of a ZIP archive.
func zipEntries(_ data: Data) -> [String] {
    let bytes = [UInt8](data)
    func u16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
    func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
    guard bytes.count >= 22,
          let end = stride(from: bytes.count - 22, through: 0, by: -1).first(where: { u32($0) == 0x0605_4B50 }) else { return [] }
    var offset = u32(end + 16)
    var names: [String] = []
    for _ in 0..<u16(end + 10) {
        guard offset + 46 <= bytes.count, u32(offset) == 0x0201_4B50 else { break }
        let nameLength = u16(offset + 28), extra = u16(offset + 30), comment = u16(offset + 32)
        names.append(String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self))
        offset += 46 + nameLength + extra + comment
    }
    return names
}

private struct Fixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("support-\(UUID().uuidString)", isDirectory: true)

    func file(_ name: String, _ text: String = "x") throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    func sources(bluetooth: String? = "GNS 2000  00-11-22-33-44-55\n") throws -> SupportPackageSources {
        let log = try file("gpsloader.log", "2026-11-14T10:00:00 [app] start\n")
        let capture = try file("capture-20261114-100000-000-mtk-ABC123.jsonl", "{}\n")
        let crash = try file("gpsloader-2026-11-14-100000.ips")
        return SupportPackageSources(appVersion: "1.0", system: { "gpsloader 1.0\n" }, logFiles: { [log] },
                                     settings: { SupportText.settings(["a": "b"]) }, portsAndUSB: { "Serial ports (0):\n" },
                                     bluetooth: bluetooth, captures: { [capture] }, crashReports: { [crash] })
    }
}

@Suite("Support package – builder")
struct SupportPackageBuilderTests {
    let date = Date(timeIntervalSince1970: 1_793_700_000)

    /// Scenario "Vollständiges Paket".
    @Test func fullPackage() async throws {
        let fixture = Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let target = fixture.directory.appendingPathComponent("out.zip")
        try await SupportPackageBuilder.build(items: Set(SupportPackageItem.allCases), sources: try fixture.sources(),
                                              to: target, date: date)
        let base = SupportPackageBuilder.baseName(for: date)
        let entries = Set(zipEntries(try Data(contentsOf: target)))
        for name in ["README.txt", "system.txt", "log/gpsloader.log", "settings.plist", "ports-and-usb.txt", "bluetooth.txt",
                     "captures/capture-20261114-100000-000-mtk-ABC123.jsonl", "crash-reports/gpsloader-2026-11-14-100000.ips"] {
            #expect(entries.contains("\(base)/\(name)"), "missing \(name)")
        }
        #expect(SupportPackageBuilder.suggestedFileName(for: date) == base + ".zip")
        #expect(base.hasPrefix("gpsloader-support-20261103-"))
    }

    /// Scenario "Inhalt abgewählt"; Bluetooth is left out when it is not available.
    @Test func deselectedParts() async throws {
        let fixture = Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let target = fixture.directory.appendingPathComponent("out.zip")
        var items = Set(SupportPackageItem.allCases)
        items.remove(.captures)
        try await SupportPackageBuilder.build(items: items, sources: try fixture.sources(bluetooth: nil), to: target, date: date)
        let entries = zipEntries(try Data(contentsOf: target))
        #expect(!entries.contains { $0.contains("captures/") })
        #expect(!entries.contains { $0.hasSuffix("bluetooth.txt") })
        #expect(entries.contains { $0.hasSuffix("system.txt") })
    }

    @Test func readmeListsTheContents() throws {
        let fixture = Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let folder = fixture.directory.appendingPathComponent("parts", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let contents = try SupportPackageBuilder.writeParts(items: [.captures, .system], sources: try fixture.sources(), into: folder)
        let readme = SupportPackageBuilder.readme(date: date, appVersion: "1.0", contents: contents)
        #expect(readme.contains("- system.txt"))
        #expect(readme.contains("captures/ – diagnostic captures of the last operations (1 files, contain positions)"))
        #expect(!readme.contains("log/"))
    }
}
