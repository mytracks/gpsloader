import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenuBuilder.makeMainMenu()

        let controller = MainWindowController()
        mainWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        #if DEBUG
        DebugAutomation.run(mainWindow: controller)
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Cancels running conversions and device operations before quitting (design D3 of change remove-gpsbabel).
    /// Everything runs in-process; the system closes open ports when the app ends.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        mainWindowController?.conversionPresenter.cancel()
        mainWindowController?.sessionPresenter.runningSessions.forEach { $0.cancel() }
        return .terminateNow
    }

    @objc func showAbout(_ sender: Any?) {
        AboutWindowController.shared.showWindow(sender)
        AboutWindowController.shared.window?.makeKeyAndOrderFront(sender)
    }
}
