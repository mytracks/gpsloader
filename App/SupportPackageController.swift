import AppKit
import BluetoothTransport
import DiagnosticCapture
import LoggerCore
import SupportPackage
import UniformTypeIdentifiers

/// "Create Support Package…" (spec `support-package`): choose the parts, save the ZIP, show it in the Finder.
@MainActor
final class SupportPackageController: NSObject {
    static let shared = SupportPackageController()

    private var isBuilding = false

    private var sources: SupportPackageSources {
        let environment = AppEnvironment.shared
        var bluetooth: String? { PairedBluetoothDevices.listIfAuthorized() }
        #if DEBUG
        // Debug automation: show the sheet as without Bluetooth permission.
        let paired = UserDefaults.standard.bool(forKey: "DebugNoBluetoothPermission") ? nil : bluetooth
        #else
        let paired = bluetooth
        #endif
        return .standard(appVersion: environment.appVersion, build: environment.build,
                         bundleIdentifier: Bundle.main.bundleIdentifier, log: .shared,
                         captureStore: environment.captureStore, bluetooth: paired)
    }

    @objc func createSupportPackage(_ sender: Any?) {
        guard !isBuilding else { return }
        let sources = sources
        let window = NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && $0.sheetParent == nil && $0.parent == nil }
        let choice = ItemChoice(captureCount: sources.captures().count, crashReportCount: sources.crashReports().count,
                                bluetoothAvailable: sources.bluetooth != nil)

        let alert = NSAlert()
        alert.messageText = String(localized: "Create Support Package")
        alert.informativeText = String(localized: "The support package collects information that helps the developer analyze a problem. It is only saved on your Mac; you decide whom to send it to.")
        alert.accessoryView = choice.view
        alert.addButton(withTitle: String(localized: "Save…"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let proceed: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            self.save(items: choice.selectedItems, sources: sources, window: window)
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: proceed) } else { proceed(alert.runModal()) }
    }

    private func save(items: Set<SupportPackageItem>, sources: SupportPackageSources, window: NSWindow?) {
        let date = Date()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = SupportPackageBuilder.suggestedFileName(for: date)
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            self.build(items: items, sources: sources, to: url, date: date)
        }
        // The alert sheet has to end before the save panel can be shown as a sheet.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let window { panel.beginSheetModal(for: window, completionHandler: handle) } else { handle(panel.runModal()) }
            }
        }
    }

    private func build(items: Set<SupportPackageItem>, sources: SupportPackageSources, to url: URL, date: Date,
                       revealInFinder: Bool = true) {
        isBuilding = true
        AppLog.shared.log(.app, "support package: " + items.map(\.rawValue).sorted().joined(separator: ", "))
        Task {
            defer { self.isBuilding = false }
            do {
                try await SupportPackageBuilder.build(items: items, sources: sources, to: url, date: date)
                if revealInFinder { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            } catch {
                let failure = error as? LoggerError ?? LoggerError(.writeFailed, detail: error.localizedDescription)
                AppLog.shared.log(.error, "support package failed: \(failure.detail)")
                (NSApp.delegate as? AppDelegate)?.sessionPresenter?.showError(failure)
            }
        }
    }

    #if DEBUG
    /// Debug automation: builds a package with all available parts at `path`, without dialogs.
    func debugBuild(to path: String) {
        let sources = sources
        var items = Set(SupportPackageItem.allCases)
        if sources.bluetooth == nil { items.remove(.bluetooth) }
        build(items: items, sources: sources, to: URL(fileURLWithPath: path), date: Date(), revealInFinder: false)
    }
    #endif
}

/// The check boxes of the support package sheet (spec "Content of the support package", "Privacy in the support package").
@MainActor
private final class ItemChoice {
    let view: NSView
    private var boxes: [SupportPackageItem: NSButton] = [:]

    init(captureCount: Int, crashReportCount: Int, bluetoothAvailable: Bool) {
        let rows: [(SupportPackageItem, String, Bool)] = [
            (.system, String(localized: "System and app information"), true),
            (.log, String(localized: "App log"), true),
            (.settings, String(localized: "Settings of myTracks Loader"), true),
            (.ports, String(localized: "Serial ports and USB devices"), true),
            (.bluetooth, bluetoothAvailable ? String(localized: "Paired Bluetooth devices")
                                            : String(localized: "Paired Bluetooth devices (no permission)"),
             bluetoothAvailable),
            (.captures, String(localized: "Diagnostic captures of the last operations (\(captureCount))"), captureCount > 0),
            (.crashReports, String(localized: "Crash reports (\(crashReportCount))"), crashReportCount > 0),
        ]
        var views: [NSView] = []
        for (item, title, enabled) in rows {
            let box = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            box.state = enabled ? .on : .off
            box.isEnabled = enabled
            boxes[item] = box
            views.append(box)
        }
        let note = NSTextField(wrappingLabelWithString: String(localized: "Diagnostic captures contain all data exchanged with the device, including recorded positions. Only send the package to people you trust, for example the developer of myTracks Loader."))
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.preferredMaxLayoutWidth = 340
        views.append(note)
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(12, after: views[views.count - 2])
        note.widthAnchor.constraint(equalToConstant: 340).isActive = true
        stack.frame = NSRect(origin: .zero, size: stack.fittingSize)
        view = stack
    }

    var selectedItems: Set<SupportPackageItem> {
        Set(boxes.filter { $0.value.isEnabled && $0.value.state == .on }.keys)
    }
}
