import Foundation
import Testing
import GPSLoggerKit
@testable import GPSLoggerKitGPL

private let packageDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// Section headings ("## ...") of a Markdown text.
func sections(in text: String) -> Set<String> {
    Set(text.split(separator: "\n").filter { $0.hasPrefix("## ") }
        .map { String($0.dropFirst(3)).trimmingCharacters(in: .whitespaces) })
}

@Suite("GPSLoggerKitGPL catalog and provenance")
struct GPLFileFormatsTests {
    /// Spec `logger-kit-gpl`, "Lizenzdatei".
    @Test func licenseIsGPLVersion3() throws {
        let text = try String(contentsOf: packageDirectory.appendingPathComponent("LICENSE"), encoding: .utf8)
        let head = text.split(separator: "\n").prefix(3).map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(head.first == "GNU GENERAL PUBLIC LICENSE")
        #expect(head.dropFirst().first == "Version 3, 29 June 2007")
        let readme = try String(contentsOf: packageDirectory.appendingPathComponent("README.md"), encoding: .utf8)
        #expect(readme.contains("GPL-3.0-or-later"))
    }

    /// Spec `logger-kit-gpl`, "Leerer Katalog" (while the package has no formats) and catalog order in general.
    @Test func combinedCatalogStartsWithGPSLoggerKit() {
        let catalog = FormatCatalog.standard.adding(GPLFileFormats.all)
        #expect(catalog.all.map(\.id) == FileFormats.all.map(\.id) + GPLFileFormats.all.map(\.id))
        if GPLFileFormats.all.isEmpty {
            #expect(catalog.all.map(\.id) == FileFormats.all.map(\.id))
        }
    }

    /// Spec `logger-kit-gpl`, "Eindeutige Kennungen".
    @Test func identifiersDifferFromGPSLoggerKit() {
        let own = GPLFileFormats.all.map(\.id)
        #expect(Set(own).count == own.count)
        #expect(Set(own).isDisjoint(with: FileFormats.all.map(\.id)))
    }

    /// Spec `logger-kit-gpl`, "Neues Format": every format has a section in PROVENANCE.md.
    @Test func everyFormatHasAProvenanceSection() throws {
        let text = try String(contentsOf: packageDirectory.appendingPathComponent("PROVENANCE.md"), encoding: .utf8)
        let found = sections(in: text)
        for format in GPLFileFormats.all {
            #expect(found.contains("`\(format.id.rawValue)`"), "PROVENANCE.md lacks a section ## `\(format.id.rawValue)`")
        }
    }

    @Test func missingSectionIsDetected() {
        let found = sections(in: "# Provenance\n\n## `wbt`\ntext\n")
        #expect(found.contains("`wbt`"))
        #expect(!found.contains("`igotu`"))
    }

    /// Every ported format needs a credited source project (design D6).
    @Test func portedFormatsAreCredited() {
        if !GPLFileFormats.all.isEmpty {
            #expect(!GPLFileFormats.credits.isEmpty)
        }
        #expect(Set(GPLFileFormats.credits).count == GPLFileFormats.credits.count)
        for credit in GPLFileFormats.credits {
            #expect(!credit.project.isEmpty && !credit.authors.isEmpty && !credit.license.isEmpty)
        }
    }

    /// Spec `logger-kit-gpl`, "SkyTraq im Katalog".
    @Test func skyTraqIsInTheCatalog() throws {
        let format = try #require(GPLFileFormats.all.first { $0.id == .skytraqBin })
        #expect(format.fileExtensions == ["bin"])
        let credit = try #require(GPLFileFormats.credits.first { $0.project == "GPSBabel" })
        #expect(credit.license == "GPL-2.0-or-later")
        #expect(credit.sourceURL.absoluteString == "https://github.com/GPSBabel/gpsbabel/tree/gpsbabel_1_7_0")
        #expect(credit.authors.contains("Mathias Adam"))
    }

    /// Spec `logger-kit-gpl`, "MTK-Formate abfragen".
    @Test func mtkIsInTheCatalog() throws {
        let ids = GPLFileFormats.all.map(\.id)
        #expect(ids.contains(.mtkBin) && ids.contains(.m241Bin))
        #expect(GPLFileFormats.all.filter { $0.id == .mtkBin || $0.id == .m241Bin }.allSatisfy { $0.fileExtensions == ["bin"] })
        let credit = try #require(GPLFileFormats.credits.first { $0.project == "GPSBabel" })
        #expect(credit.authors.contains("Per Borgentun"))
        #expect(GPLFileFormats.credits.map(\.project) == ["GPSBabel", "igotu2gpx"])
    }
}
