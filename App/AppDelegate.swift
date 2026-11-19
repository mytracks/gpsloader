import AppKit
import DiagnosticCapture
import LoggerCore
import SupportPackage

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?

    var sessionPresenter: SessionPresenter? { mainWindowController?.sessionPresenter }

    /// Folders of earlier builds named "gpsloader", moved before the log and the capture store write anything
    /// (spec `support-package`, "App-Protokoll"; design D2 of change rename-and-icon).
    private var folderMigrations: [(String, LegacyFolderMigration.Outcome)] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        folderMigrations = [
            ("log", LegacyFolderMigration.migrate(from: AppLog.legacyDirectory, to: AppLog.defaultDirectory)),
            ("support", LegacyFolderMigration.migrate(from: CaptureStore.legacySupportDirectory,
                                                       to: CaptureStore.supportDirectory)),
        ]
        AppLog.shared.adoptLegacyFiles()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment.shared
        let system = SystemReport.current(appVersion: environment.appVersion, build: environment.build)
        for (folder, outcome) in folderMigrations where outcome != .nothingToMove {
            AppLog.shared.log(outcome == .moved || outcome == .keptBoth ? .app : .error,
                              "legacy \(folder) folder: \(outcome)")
        }
        AppLog.shared.log(.app, "start \(ProductName.name) \(system.appVersion) (\(system.build)), macOS \(system.osVersion), "
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
