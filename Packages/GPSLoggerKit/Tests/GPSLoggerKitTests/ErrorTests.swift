import Foundation
import Testing
@testable import GPSLoggerKit

@Suite("Errors and warnings")
struct ErrorTests {
    private static let kinds: [GPSLoggerErrorKind] = [.unreadable, .empty, .malformed(line: 12), .noUsableData, .writeFailed]

    @Test(arguments: ["de", "en"])
    func everyErrorHasALocalizedMessage(localization: String) {
        #expect(Self.kinds.map(\.key) == GPSLoggerErrorKind.allKeys)
        for kind in Self.kinds {
            let message = GPSLoggerError.message(for: kind, fileName: "a.nmea", localization: localization)
            #expect(!message.isEmpty)
            #expect(!message.hasPrefix("error."), "missing translation for \(kind)")
            #expect(message.contains("a.nmea"))
        }
    }

    @Test func messagesDifferBetweenLanguages() {
        let de = GPSLoggerError.message(for: .empty, fileName: "x", localization: "de")
        let en = GPSLoggerError.message(for: .empty, fileName: "x", localization: "en")
        #expect(de != en)
    }

    @Test func malformedMessageNamesTheLine() {
        #expect(GPSLoggerError.message(for: .malformed(line: 12), fileName: "x.gpx", localization: "de").contains("Zeile 12"))
        #expect(GPSLoggerError.message(for: .malformed(line: 12), fileName: "x.gpx", localization: "en").contains("line 12"))
    }

    @Test(arguments: ["de", "en"])
    func everyWarningHasALocalizedMessage(localization: String) {
        for kind in ImportWarningKind.allCases {
            let message = ImportWarning(kind: kind, count: 3, fileName: "a.nmea").message(localization: localization)
            #expect(!message.hasPrefix("warning."), "missing translation for \(kind)")
            #expect(message.contains("3") && message.contains("a.nmea"))
        }
    }

    @Test func collectorCountsPerKindAndKeepsTheFirstLine() {
        var collector = WarningCollector(fileName: "f")
        collector.add(.checksumMismatch, line: 7)
        collector.add(.checksumMismatch, line: 9)
        collector.add(.missingDate, line: nil, count: 5)
        #expect(collector.warnings == [
            ImportWarning(kind: .checksumMismatch, count: 2, fileName: "f", firstLine: 7),
            ImportWarning(kind: .missingDate, count: 5, fileName: "f", firstLine: nil),
        ])
    }
}
