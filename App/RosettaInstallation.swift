import AppKit

/// Offers the installation of Rosetta (spec `gpsbabel-runtime`, "Rosetta-Installation anbieten", design.md D6).
///
/// Opens the bundled x86_64-only `RosettaInstaller.app`; without Rosetta, macOS shows its own installation
/// dialog. Afterwards the runtime is re-checked whenever the app becomes active and every few seconds for up
/// to 10 minutes, so no restart is needed. If the helper cannot be opened, the Terminal command is shown.
@MainActor
final class RosettaInstallation {
    static let shared = RosettaInstallation()

    static let terminalCommand = "softwareupdate --install-rosetta --agree-to-license"

    private var pollTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?

    func start(presentingWindow window: NSWindow?) {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/RosettaInstaller.app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: helper, configuration: configuration) { _, error in
            Task { @MainActor in
                if error != nil {
                    self.showFallback(window: window)
                }
                self.watchForInstallation()
            }
        }
    }

    /// Shows the Terminal command as fallback.
    func showFallback(window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Install Rosetta manually")
        alert.informativeText = String(localized: "The system dialog for installing Rosetta could not be opened. Open Terminal, enter the following command and confirm with your administrator password:")
            + "\n\n" + Self.terminalCommand
        alert.addButton(withTitle: String(localized: "Copy Command"))
        alert.addButton(withTitle: String(localized: "OK"))
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Self.terminalCommand, forType: .string)
            }
        }
        if let window {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    private func watchForInstallation() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            let deadline = Date().addingTimeInterval(10 * 60)
            while !Task.isCancelled, Date() < deadline {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if await self.recheck() { break }
            }
            self.stopWatching()
        }
        if activationObserver == nil {
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { _ in
                Task { @MainActor in
                    if await self.recheck() { self.stopWatching() }
                }
            }
        }
    }

    /// Re-checks the runtime; returns `true` when Rosetta is no longer missing.
    private func recheck() async -> Bool {
        let environment = AppEnvironment.shared
        environment.refreshRuntime()
        let status = await environment.runtime.refresh()
        return status != .rosettaMissing
    }

    private func stopWatching() {
        pollTask?.cancel()
        pollTask = nil
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        activationObserver = nil
    }
}
