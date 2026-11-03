import AppKit
import GPSBabelRuntime

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenuBuilder.makeMainMenu()

        let controller = MainWindowController()
        mainWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Asynchronous check; the UI shows "checking" meanwhile (spec gpsbabel-runtime).
        AppEnvironment.shared.refreshRuntime()

        #if DEBUG
        DebugAutomation.run(mainWindow: controller)
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Cancels running operations and terminates child processes (gpsbabel) before quitting
    /// (spec `gpsbabel-runtime`, "App wird während eines Aufrufs beendet").
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let sessions = mainWindowController?.sessionPresenter.runningSessions ?? []
        let registry = ProcessRegistry.shared
        guard !isTerminating, !sessions.isEmpty || !registry.runningProcesses.isEmpty else {
            return .terminateNow
        }
        isTerminating = true
        sessions.forEach { $0.cancel() }
        // While waiting after `.terminateLater`, the main run loop runs in the modal panel mode, where
        // main-actor jobs are not executed. So clean up off the main actor and reply via a run-loop block
        // that is allowed to run in that mode.
        Task.detached {
            await registry.terminateAll(grace: 3)
            RunLoop.main.perform(inModes: [.default, .modalPanel]) {
                MainActor.assumeIsolated {
                    NSApp.reply(toApplicationShouldTerminate: true)
                }
            }
        }
        return .terminateLater
    }

    @objc func showAbout(_ sender: Any?) {
        AboutWindowController.shared.showWindow(sender)
        AboutWindowController.shared.window?.makeKeyAndOrderFront(sender)
    }
}
