import AppKit
import DiagnosticCapture
import LoggerCore

/// Shared app state: port reservations and diagnostic capture storage.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let appVersion: String
    let reservations = PortReservations()
    let captureStore = CaptureStore()

    private init() {
        appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Creator string for GPX files.
    var gpxCreator: String { "gpsloader \(appVersion)" }

    /// A new capture recorder if diagnostic capture is switched on.
    func makeRecorderIfEnabled() -> CaptureRecorder? {
        guard captureStore.isEnabled else { return nil }
        return CaptureRecorder(environment: .current(appVersion: appVersion))
    }
}
