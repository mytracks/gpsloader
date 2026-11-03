#if DEBUG
import AppKit
import GPSBabelRuntime
import LoggerCore

/// Debug-only launch arguments for verifying UI states without screen recording permission:
///
///     -DebugSnapshotDirectory <dir>     render all visible windows to PNG (repeatedly, see times below)
///     -DebugSimulatedStatus <checking|ready|rosetta|broken>
///     -DebugDemo <scenario>             start reading with the demo driver (scenarios of DemoDriver)
///     -DebugDemoErase <supported|experimental>   start erasing with the demo driver
///     -DebugShowAbout YES
///     -DebugShowCaptureExport <seconds>  open "Save Latest Diagnostic Capture…" after the given delay
///     -DebugCancelAfter <seconds>       press "Cancel" on running operations
///     -DebugSaveDirectory <dir>         save results there without the save panel (see SessionPresenter)
///     -DebugQuitAfter <seconds>
@MainActor
enum DebugAutomation {
    static func run(mainWindow: MainWindowController) {
        let defaults = UserDefaults.standard

        switch defaults.string(forKey: "DebugSimulatedStatus") {
        case "checking": AppEnvironment.shared.simulatedStatus = .checking
        case "ready": AppEnvironment.shared.simulatedStatus = .ready(version: "1.7.0")
        case "rosetta": AppEnvironment.shared.simulatedStatus = .rosettaMissing
        case "broken": AppEnvironment.shared.simulatedStatus = .broken(reason: "Simulated: dyld: Library not loaded: QtCoreGpsBabel")
        default: break
        }

        if defaults.bool(forKey: "DebugShowAbout") {
            (NSApp.delegate as? AppDelegate)?.showAbout(nil)
        }

        if let scenario = defaults.string(forKey: "DebugDemo").flatMap(DemoDriver.Scenario.init(rawValue:)) {
            mainWindow.sessionPresenter.read(with: DemoDriver(scenario: scenario, erase: .supported))
        }
        if let mode = defaults.string(forKey: "DebugDemoErase") {
            let erase: EraseSupport = mode == "experimental" ? .experimental : .supported
            mainWindow.sessionPresenter.erase(with: DemoDriver(scenario: .success, erase: erase))
        }

        if let directory = defaults.string(forKey: "DebugSnapshotDirectory") {
            for delay in [1.0, 2.5, 5.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    MainActor.assumeIsolated { snapshotWindows(to: URL(fileURLWithPath: directory), tag: "t\(delay)") }
                }
            }
        }

        let exportAfter = defaults.double(forKey: "DebugShowCaptureExport")
        if exportAfter > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + exportAfter) {
                MainActor.assumeIsolated { DiagnosticsController.shared.saveLatestCapture(nil) }
            }
        }

        let cancelAfter = defaults.double(forKey: "DebugCancelAfter")
        if cancelAfter > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + cancelAfter) {
                MainActor.assumeIsolated {
                    mainWindow.sessionPresenter.runningSessions.forEach { $0.cancel() }
                }
            }
        }

        let quitAfter = defaults.double(forKey: "DebugQuitAfter")
        if quitAfter > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + quitAfter) {
                MainActor.assumeIsolated { NSApp.terminate(nil) }
            }
        }
    }

    static func snapshotWindows(to directory: URL, tag: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, window) in NSApp.windows.enumerated() where window.isVisible {
            guard let view = window.contentView?.superview ?? window.contentView else { continue }
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let name = window.title.isEmpty ? "window\(index)" : window.title
            let safe = name.filter { $0.isLetter || $0.isNumber }
            let url = directory.appendingPathComponent("\(tag)-\(index)-\(safe).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }
}
#endif
