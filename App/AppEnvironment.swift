import AppKit
import DiagnosticCapture
import GPSBabelRuntime
import LoggerCore

/// Shared app state: gpsbabel runtime status, port reservations and diagnostic capture storage.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let appVersion: String
    let gpsbabelLocation: GPSBabelLocation
    let runtime: GPSBabelRuntime
    let reservations = PortReservations()
    let captureStore = CaptureStore()

    /// Last known gpsbabel status. Observers are notified on every change.
    private(set) var runtimeStatus: GPSBabelStatus = .checking {
        didSet { statusObservers.forEach { $0(displayedStatus) } }
    }

    #if DEBUG
    /// Debug-only override to show every status in the UI (task 7.1).
    var simulatedStatus: GPSBabelStatus? {
        didSet { statusObservers.forEach { $0(displayedStatus) } }
    }
    #endif

    /// The status the UI shows.
    var displayedStatus: GPSBabelStatus {
        #if DEBUG
        if let simulatedStatus { return simulatedStatus }
        #endif
        return runtimeStatus
    }

    private var statusObservers: [(GPSBabelStatus) -> Void] = []

    private init() {
        appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        gpsbabelLocation = GPSBabelLocation.bundled(in: Bundle.main.bundleURL)
        runtime = GPSBabelRuntime(probe: GPSBabelProbe(location: gpsbabelLocation))
    }

    func observeStatus(_ observer: @escaping (GPSBabelStatus) -> Void) {
        statusObservers.append(observer)
        observer(displayedStatus)
    }

    /// Checks gpsbabel asynchronously; the UI stays usable and shows "checking" meanwhile.
    func refreshRuntime() {
        runtimeStatus = .checking
        let runtime = self.runtime
        Task {
            let status = await runtime.refresh()
            self.runtimeStatus = status
        }
    }

    /// Creator string for GPX files.
    var gpxCreator: String { "gpsloader \(appVersion)" }

    /// A new capture recorder if diagnostic capture is switched on.
    func makeRecorderIfEnabled() -> CaptureRecorder? {
        guard captureStore.isEnabled else { return nil }
        return CaptureRecorder(environment: .current(appVersion: appVersion))
    }
}
