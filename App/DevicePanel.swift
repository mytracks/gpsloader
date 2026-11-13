import AppKit
import DeviceDrivers
import LoggerCore
import SerialTransport

/// The "Device" section of the main window (spec `device-mode`): device and port selection, read and erase.
@MainActor
final class DevicePanel: NSObject {
    private let sessionPresenter: SessionPresenter
    private let entries = DeviceCatalog.entries
    private var ports: [SerialPortInfo] = []
    private var selection = DeviceSelection()
    private var portTask: Task<Void, Never>?

    private let devicePopup = NSPopUpButton()
    private let portPopup = NSPopUpButton()
    private let portLabel = NSTextField(labelWithString: String(localized: "Port:"))
    private let hintLabel = NSTextField(wrappingLabelWithString: "")
    private lazy var readButton = NSButton(title: String(localized: "Read"), target: self, action: #selector(read(_:)))
    private lazy var eraseButton = NSButton(title: String(localized: "Erase Memory…"), target: self, action: #selector(erase(_:)))

    static let defaultsKey = "DeviceSelection"

    /// The HID transport used for USB HID devices (i-GotU); set by the app if available.
    var hidFactory: (any HIDConnectionFactory)?

    init(sessionPresenter: SessionPresenter) {
        self.sessionPresenter = sessionPresenter
        super.init()
    }

    /// Builds the content of the section. Without drivers it shows the former placeholder.
    func makeView() -> NSView {
        guard !entries.isEmpty else {
            let placeholder = NSTextField(wrappingLabelWithString: String(localized: "Device drivers will be added in upcoming versions."))
            placeholder.textColor = .secondaryLabelColor
            return placeholder
        }
        devicePopup.addItems(withTitles: entries.map(\.name))
        devicePopup.target = self
        devicePopup.action = #selector(deviceChanged(_:))
        portPopup.target = self
        portPopup.action = #selector(portChanged(_:))
        hintLabel.textColor = .secondaryLabelColor
        readButton.keyEquivalent = "\r"

        ports = SerialPortCatalog.currentPorts()
        let stored = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String]
        selection = DeviceSelection.restore(DeviceSelection(stored: stored), entries: entries, ports: ports)
        reloadPorts()
        if let index = entries.firstIndex(where: { $0.id == selection.entryID }) { devicePopup.selectItem(at: index) }
        update()

        portTask = Task { @MainActor [weak self] in
            for await _ in SerialPortCatalog.changes() {
                guard let self else { return }
                self.ports = SerialPortCatalog.currentPorts()
                self.selection.portPath = DeviceSelection.port(preferring: self.selection.portPath, in: self.ports)
                self.reloadPorts()
                self.update()
            }
        }

        let deviceRow = NSStackView(views: [NSTextField(labelWithString: String(localized: "Device:")), devicePopup])
        let portRow = NSStackView(views: [portLabel, portPopup])
        let buttons = NSStackView(views: [readButton, eraseButton])
        let stack = NSStackView(views: [deviceRow, portRow, hintLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        hintLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    /// Called by the window when a session starts or ends.
    func update() {
        let entry = selection.entry(in: entries)
        let needsPort = entry?.needsPort ?? true
        portLabel.isHidden = !needsPort
        portPopup.isHidden = !needsPort
        let running = sessionPresenter.isRunning
        readButton.isEnabled = selection.canRead(entries: entries, isRunning: running)
        eraseButton.isHidden = entry?.eraseSupport == .unsupported
        eraseButton.isEnabled = selection.canErase(entries: entries, isRunning: running)
        switch selection.hint(entries: entries) {
        case .noPort:
            hintLabel.stringValue = String(localized: "No serial port found. Connect the logger or pair it via Bluetooth.")
            hintLabel.isHidden = false
        case nil:
            hintLabel.stringValue = ""
            hintLabel.isHidden = true
        }
        UserDefaults.standard.set(selection.stored, forKey: Self.defaultsKey)
    }

    private func reloadPorts() {
        portPopup.removeAllItems()
        for port in ports {
            portPopup.addItem(withTitle: port.name == port.path ? port.path : "\(port.name) (\(port.path))")
        }
        if let index = ports.firstIndex(where: { $0.path == selection.portPath }) { portPopup.selectItem(at: index) }
    }

    @objc private func deviceChanged(_ sender: NSPopUpButton) {
        selection.entryID = entries[max(sender.indexOfSelectedItem, 0)].id
        update()
    }

    @objc private func portChanged(_ sender: NSPopUpButton) {
        guard ports.indices.contains(sender.indexOfSelectedItem) else { return }
        selection.portPath = ports[sender.indexOfSelectedItem].path
        update()
    }

    private var driver: ProtocolDriver? {
        guard let entry = selection.entry(in: entries) else { return nil }
        return ProtocolDriver(entry: entry, portPath: entry.needsPort ? selection.portPath : nil, hidFactory: hidFactory)
    }

    #if DEBUG
    /// Debug automation: selects a catalog entry and port, then reads or erases (erasing skips the confirmation
    /// sheet only if the session presenter does; here it uses the normal flow).
    func debugRun(entryID: String, portPath: String?, erase: Bool) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        devicePopup.selectItem(at: index)
        selection = DeviceSelection(entryID: entryID, portPath: portPath ?? selection.portPath)
        guard let driver else { return }
        if erase {
            sessionPresenter.erase(with: driver)
        } else {
            sessionPresenter.read(with: driver)
        }
        update()
    }
    #endif

    @objc func read(_ sender: Any?) {
        guard let driver, selection.canRead(entries: entries, isRunning: sessionPresenter.isRunning) else { return }
        sessionPresenter.read(with: driver)
        update()
    }

    @objc func erase(_ sender: Any?) {
        guard let driver, selection.canErase(entries: entries, isRunning: sessionPresenter.isRunning) else { return }
        sessionPresenter.erase(with: driver)
        update()
    }
}
