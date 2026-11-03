import AppKit
import DiagnosticCapture

/// Menu actions for the diagnostic capture (spec `diagnostic-capture`).
@MainActor
final class DiagnosticsController: NSObject, NSMenuItemValidation {
    static let shared = DiagnosticsController()

    private var store: CaptureStore { AppEnvironment.shared.captureStore }

    @objc func toggleCapture(_ sender: Any?) {
        store.isEnabled.toggle()
    }

    /// Spec "Export für den Support": warn about position data, then save.
    @objc func saveLatestCapture(_ sender: Any?) {
        guard let latest = store.latest() else { return }
        let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && $0.sheetParent == nil }

        let alert = NSAlert()
        alert.messageText = String(localized: "Save diagnostic capture?")
        alert.informativeText = String(localized: "The capture contains all data exchanged with the device, including recorded positions. Only send it to people you trust, for example the developer of gpsloader.")
        alert.addButton(withTitle: String(localized: "Continue"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        let proceed: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = latest.lastPathComponent
            let save: (NSApplication.ModalResponse) -> Void = { result in
                guard result == .OK, let target = panel.url else { return }
                do {
                    if FileManager.default.fileExists(atPath: target.path) {
                        try FileManager.default.removeItem(at: target)
                    }
                    try FileManager.default.copyItem(at: latest, to: target)
                } catch {
                    NSAlert(error: error).runModal()
                }
            }
            if let window { panel.beginSheetModal(for: window, completionHandler: save) } else { save(panel.runModal()) }
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: proceed) } else { proceed(alert.runModal()) }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleCapture(_:)):
            menuItem.state = store.isEnabled ? .on : .off
            return true
        case #selector(saveLatestCapture(_:)):
            return store.latest() != nil
        default:
            return true
        }
    }
}
