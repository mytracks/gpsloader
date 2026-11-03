import Foundation
import Testing
@testable import LoggerCore

@Suite("LoggerError")
struct LoggerErrorTests {
    @Test(arguments: LoggerErrorKind.allCases, ["en", "de"])
    func everyKindHasAMessage(kind: LoggerErrorKind, localization: String) {
        let message = LoggerError.message(for: kind, localization: localization)
        #expect(!message.isEmpty)
        #expect(!message.hasPrefix("error."), "missing \(localization) translation for \(kind)")
    }

    @Test func germanAndEnglishDiffer() {
        let en = LoggerError.message(for: .timeout, localization: "en")
        let de = LoggerError.message(for: .timeout, localization: "de")
        #expect(en != de)
        #expect(de.contains("Zeitüberschreitung"))
    }

    @Test func detailIsKeptAsFailureReason() {
        let error = LoggerError(.portBusy, detail: "/dev/cu.SLAB_USBtoUART")
        #expect(error.failureReason == "/dev/cu.SLAB_USBtoUART")
        #expect(error.errorDescription?.isEmpty == false)
    }

    @Test func timeoutSuggestsCheckingConnection() {
        let suggestion = LoggerError.recoverySuggestion(for: .timeout, localization: "de")
        #expect(suggestion?.contains("Verbindung") == true)
        #expect(LoggerError.recoverySuggestion(for: .cancelled, localization: "en") == nil)
    }
}
