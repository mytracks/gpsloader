import AppKit
import SupportPackage

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?

    var sessionPresenter: SessionPresenter? { mainWindowController?.sessionPresenter }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment.shared
        let system = SystemReport.current(appVersion: environment.appVersion, build: environment.build)
        AppLog.shared.log(.app, "start gpsloader \(system.appVersion) (\(system.build)), macOS \(system.osVersion), "
            + "\(system.model), \(system.architecture)\(system.isTranslated ? " (Rosetta)" : "")")
        NSApp.mainMenu = MainMenuBuilder.makeMainMenu()

        let controller = MainWindowController()
        mainWindowController = controller
        // The section commands always act on the main window, also while another window (About) is key.
        let sectionActions = [#selector(MainWindowController.showFilesSection(_:)), #selector(MainWindowController.showDeviceSection(_:))]
        for item in NSApp.mainMenu?.items.flatMap({ $0.submenu?.items ?? [] }) ?? [] where sectionActions.contains(where: { $0 == item.action }) {
            item.target = controller
        }
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
