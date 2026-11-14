import AppKit
import DiagnosticCapture
import LoggerCore

/// Shared app state: port reservations and diagnostic capture storage.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let appVersion: String
    let build: String
    let reservations = PortReservations()
    let captureStore = CaptureStore()

    private init() {
        appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// Creator string for GPX files.
    var gpxCreator: String { "gpsloader \(appVersion)" }

    /// The capture of a new operation; diagnostic capture is always on (spec `diagnostic-capture`).
    func makeCapture(header: DiagnosticHeader) -> OperationCapture {
        OperationCapture(store: captureStore, environment: .current(appVersion: appVersion), header: header)
    }
}
