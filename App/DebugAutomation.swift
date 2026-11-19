#if DEBUG
import AppKit
import LoggerCore

/// Debug-only launch arguments for verifying UI states without screen recording permission:
///
///     -DebugSnapshotDirectory <dir>     render all visible windows to PNG (repeatedly, see times below)
///     -DebugSnapshotTimes <s>[,<s>…]   snapshot times instead of 1, 2.5 and 5 seconds
///     -DebugDemo <scenario>             start reading with the demo driver (scenarios of DemoDriver)
///     -DebugDemoErase <supported|experimental>   start erasing with the demo driver
///     -DebugShowAbout YES
///     -DebugShowSupportPackage <seconds> open "Create Support Package…" after the given delay
///     -DebugSupportPackagePath <file>   write a support package with all available parts, without dialogs
///     -DebugNoBluetoothPermission YES   treat the Bluetooth permission as missing in the support package
///     -DebugCancelAfter <seconds>       press "Cancel" on running operations
///     -DebugSaveDirectory <dir>         save results there without the save panel (see SessionPresenter)
///     -DebugConvert <path>[,<path>…]    convert these files as if chosen in "Convert Files…" (ConversionPresenter)
///     -DebugReadDevice <catalog id> [-DebugPort <path>] [-DebugErase YES]   read/erase a catalog device
///     -DebugSelectDevice <catalog id> [-DebugPort <path>]   only select a catalog device (for snapshots)
///     -DebugPorts <specs> / -DebugUSBDevices <specs>   fake port and USB lists (see DebugPorts in DevicePanel.swift)
///     -DebugSection files|device        show this section of the main window first
///     -DebugKeyEquivalent <key>         after 1.5 s, send ⌘<key> through the main menu (e.g. 2 for "Read Device")
///     -DebugQuitAfter <seconds>
@MainActor
enum DebugAutomation {
    static func run(mainWindow: MainWindowController) {
        let defaults = UserDefaults.standard

        if let section = defaults.string(forKey: "DebugSection").flatMap(MainWindowSection.init(rawValue:)) {
            mainWindow.select(section)
        }
        if let key = defaults.string(forKey: "DebugKeyEquivalent"), !key.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                MainActor.assumeIsolated {
                    guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                                       windowNumber: mainWindow.window?.windowNumber ?? 0, context: nil,
                                                       characters: key, charactersIgnoringModifiers: key, isARepeat: false,
                                                       keyCode: 0) else { return }
                    _ = NSApp.mainMenu?.performKeyEquivalent(with: event)
                }
            }
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

        // -DebugReadDevice <catalog id> [-DebugPort <path>] [-DebugErase YES]: read (or erase) a device of the
        // catalog without the UI, e.g. against a simulated logger on a pseudo terminal (change device-mode).
        if let deviceID = defaults.string(forKey: "DebugReadDevice") {
            mainWindow.devicePanel.debugRun(entryID: deviceID, portPath: defaults.string(forKey: "DebugPort"),
                                            erase: defaults.bool(forKey: "DebugErase"))
        }

        if let deviceID = defaults.string(forKey: "DebugSelectDevice") {
            mainWindow.devicePanel.debugSelect(entryID: deviceID, portPath: defaults.string(forKey: "DebugPort"))
        }

        if let paths = defaults.string(forKey: "DebugConvert") {
            let urls = paths.split(separator: ",").map { URL(fileURLWithPath: String($0)) }
            mainWindow.convertDropped(urls)
        }

        if let directory = defaults.string(forKey: "DebugSnapshotDirectory") {
            let times = defaults.string(forKey: "DebugSnapshotTimes")?.split(separator: ",").compactMap { Double($0) }
            for delay in times ?? [1.0, 2.5, 5.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    MainActor.assumeIsolated { snapshotWindows(to: URL(fileURLWithPath: directory), tag: "t\(delay)") }
                }
            }
        }

        let supportAfter = defaults.double(forKey: "DebugShowSupportPackage")
        if supportAfter > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + supportAfter) {
                MainActor.assumeIsolated { SupportPackageController.shared.createSupportPackage(nil) }
            }
        }
        if let path = defaults.string(forKey: "DebugSupportPackagePath") {
            SupportPackageController.shared.debugBuild(to: path)
        }

        let cancelAfter = defaults.double(forKey: "DebugCancelAfter")
        if cancelAfter > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + cancelAfter) {
                MainActor.assumeIsolated {
                    mainWindow.sessionPresenter.runningSessions.forEach { $0.cancel() }
                    mainWindow.conversionPresenter.cancel()
                }
            }
        }

        let quitAfter = defaults.double(forKey: "DebugQuitAfter")
        if quitAfter > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + quitAfter) {
                MainActor.assumeIsolated {
                    // AppKit refuses to quit while the two-button question sheet is open; close it first.
                    mainWindow.conversionPresenter.cancel()
                    // Alerts with completion handlers (errors offering the support package) also block quitting.
                    for window in NSApp.windows {
                        if let sheet = window.attachedSheet { window.endSheet(sheet) }
                    }
                    NSApp.terminate(nil)
                }
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
        // Menus cannot be captured as images; their titles go into a text file next to the snapshots.
        if let appMenu = NSApp.mainMenu?.items.first?.submenu {
            let lines = [appMenu.title] + appMenu.items.filter { !$0.isSeparatorItem }.map { "  " + $0.title }
            try? (lines.joined(separator: "\n") + "\n").write(to: directory.appendingPathComponent("\(tag)-app-menu.txt"),
                                                            atomically: true, encoding: .utf8)
        }
    }
}
#endif
