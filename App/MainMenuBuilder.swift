import AppKit

/// Builds the main menu in code (no nib).
@MainActor
enum MainMenuBuilder {
    static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(makeAppMenuItem())
        mainMenu.addItem(makeFileMenuItem())
        mainMenu.addItem(makeEditMenuItem())
        mainMenu.addItem(makeViewMenuItem())
        mainMenu.addItem(makeWindowMenuItem())
        mainMenu.addItem(makeHelpMenuItem())
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

    /// "Ablage" menu (spec `file-conversion`, "Dateien auswählen"). The action goes through the responder chain
    /// to the main window controller.
    private static func makeFileMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: String(localized: "File"))
        menu.addItem(withTitle: String(localized: "Convert Files…"),
                     action: #selector(MainWindowController.convertFiles(_:)), keyEquivalent: "o")
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
    /// "Help" with "Create Support Package…" (spec `support-package`).
    private static func makeHelpMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: String(localized: "Help"))
        let create = menu.addItem(withTitle: String(localized: "Create Support Package…"),
                                  action: #selector(SupportPackageController.createSupportPackage(_:)), keyEquivalent: "")
        create.target = SupportPackageController.shared
        item.submenu = menu
        NSApp.helpMenu = menu
        return item
    }

    /// "View" with the two sections of the main window (spec `app-shell`, "Bereiche des Hauptfensters").
    private static func makeViewMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: String(localized: "View"))
        menu.addItem(withTitle: MainWindowSection.files.title,
                     action: #selector(MainWindowController.showFilesSection(_:)), keyEquivalent: "1")
        menu.addItem(withTitle: MainWindowSection.device.title,
                     action: #selector(MainWindowController.showDeviceSection(_:)), keyEquivalent: "2")
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
