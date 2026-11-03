import AppKit

/// Builds the main menu in code (no nib).
@MainActor
enum MainMenuBuilder {
    static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(makeAppMenuItem())
        mainMenu.addItem(makeEditMenuItem())
        mainMenu.addItem(makeWindowMenuItem())
        mainMenu.addItem(makeDiagnosticsMenuItem())
        return mainMenu
    }

    private static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "gpsloader"
    }

    private static func makeAppMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: appName)

        menu.addItem(withTitle: String(localized: "About \(appName)"),
                     action: #selector(AppDelegate.showAbout(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())

        let servicesItem = NSMenuItem(title: String(localized: "Services"), action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu()
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        menu.addItem(servicesItem)
        menu.addItem(.separator())

        menu.addItem(withTitle: String(localized: "Hide \(appName)"),
                     action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = menu.addItem(withTitle: String(localized: "Hide Others"),
                                      action: #selector(NSApplication.hideOtherApplications(_:)),
                                      keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: String(localized: "Show All"),
                     action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Quit \(appName)"),
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        item.submenu = menu
        return item
    }

    private static func makeEditMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: String(localized: "Edit"))
        menu.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        item.submenu = menu
        return item
    }

    /// "Diagnose" menu (spec `diagnostic-capture`).
    private static func makeDiagnosticsMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: String(localized: "Diagnostics"))
        let controller = DiagnosticsController.shared
        let toggle = menu.addItem(withTitle: String(localized: "Record Diagnostic Capture"),
                                  action: #selector(DiagnosticsController.toggleCapture(_:)), keyEquivalent: "")
        toggle.target = controller
        let save = menu.addItem(withTitle: String(localized: "Save Latest Diagnostic Capture…"),
                                action: #selector(DiagnosticsController.saveLatestCapture(_:)), keyEquivalent: "")
        save.target = controller
        item.submenu = menu
        return item
    }

    private static func makeWindowMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: String(localized: "Window"))
        menu.addItem(withTitle: String(localized: "Minimize"),
                     action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: String(localized: "Close"),
                     action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        item.submenu = menu
        NSApp.windowsMenu = menu
        return item
    }
}
