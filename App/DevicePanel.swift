import AppKit
import DeviceDrivers
import LoggerCore
import SerialTransport
import SupportPackage

/// The "Read Device" section of the main window (spec `device-mode`): device and port selection with readable
/// names, hints for the device, read and erase.
@MainActor
final class DevicePanel: NSObject {
    private let sessionPresenter: SessionPresenter
    private let entries = DeviceCatalog.entries
    private var ports: [SerialPortInfo] = []
    /// The ports in the order of the popup (system ports left out).
    private var visiblePorts: [PresentedPort] = []
    private var usbDevices: [USBDeviceInfo] = []
    private var selection = DeviceSelection()
    private var portTask: Task<Void, Never>?
    private var usbTask: Task<Void, Never>?
    /// Driver pages of the link buttons in the hint area, by tag.
    private var hintLinks: [URL] = []

    private let devicePopup = NSPopUpButton()
    private let portPopup = NSPopUpButton()
    private let portLabel = NSTextField(labelWithString: String(localized: "Port:"))
    private let hintStack = NSStackView()
    private lazy var readButton = NSButton(title: String(localized: "Read"), target: self, action: #selector(read(_:)))
    private lazy var eraseButton = NSButton(title: String(localized: "Erase Memory…"), target: self, action: #selector(erase(_:)))

    static let defaultsKey = "DeviceSelection"

    /// The HID transport used for USB HID devices (i-GotU); set by the app if available.
    var hidFactory: (any HIDConnectionFactory)?
    var bluetoothFactory: (any BluetoothTransportFactory)?

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
        hintStack.orientation = .vertical
        hintStack.alignment = .leading
        hintStack.spacing = 6
        readButton.keyEquivalent = "\r"

        ports = Self.currentPorts()
        usbDevices = Self.currentUSBDevices()
        AppLog.shared.log(.ports, "ports: " + (ports.isEmpty ? "none" : ports.map { "\($0.path) (\($0.kind.rawValue))" }.joined(separator: ", ")))
        let stored = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String]
        selection = DeviceSelection.restore(DeviceSelection(stored: stored), entries: entries, ports: ports)
        reloadPorts()
        if let index = entries.firstIndex(where: { $0.id == selection.entryID }) { devicePopup.selectItem(at: index) }
        update()

        portTask = Task { @MainActor [weak self] in
            for await change in SerialPortCatalog.changes() {
                switch change {
                case let .added(port):
                    AppLog.shared.log(.ports, "added \(port.path) (\(port.kind.rawValue))" + (port.isUSB
                        ? String(format: " USB 0x%04X:0x%04X", port.usbVendorID ?? 0, port.usbProductID ?? 0) : ""))
                case let .removed(path):
                    AppLog.shared.log(.ports, "removed \(path)")
                }
                guard let self else { return }
                self.portsChanged()
            }
        }
        // A USB-serial adapter without driver creates no port; only the USB notification shows it (design D5).
        usbTask = Task { @MainActor [weak self] in
            for await _ in USBDeviceCatalog.changes() {
                guard let self else { return }
                self.portsChanged()
            }
        }

        let deviceRow = NSStackView(views: [NSTextField(labelWithString: String(localized: "Device:")), devicePopup])
        let portRow = NSStackView(views: [portLabel, portPopup])
        let buttons = NSStackView(views: [readButton, eraseButton])
        let stack = NSStackView(views: [deviceRow, portRow, hintStack, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.detachesHiddenViews = true
        hintStack.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func portsChanged() {
        ports = Self.currentPorts()
        usbDevices = Self.currentUSBDevices()
        selection.portPath = DeviceSelection.port(preferring: selection.portPath, in: ports, for: selection.entry(in: entries))
        reloadPorts()
        update()
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
        showHints(selection.hints(entries: entries, ports: ports, usbDevices: usbDevices), device: entry?.name ?? "")
        UserDefaults.standard.set(selection.stored, forKey: Self.defaultsKey)
    }

    // MARK: - Hints (spec "Device hints", "Missing driver")

    private func showHints(_ hints: [DeviceSelection.Hint], device: String) {
        hintStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        hintLinks = []
        for hint in hints {
            switch hint {
            case .noPort:
                addHint(String(localized: "No serial port found. Connect the logger or pair it via Bluetooth."))
            case let .device(message):
                addHint(Self.text(for: message, device: device))
            case let .driverMissing(chip):
                addHint(String(localized: "A USB device with a \(chip.name) chip is connected, but macOS has not created a port for it. The driver is probably missing."),
                        link: chip.driverPage)
            }
        }
        hintStack.isHidden = hints.isEmpty
    }

    private func addHint(_ text: String, link: URL? = nil) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.textColor = .secondaryLabelColor
        hintStack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: hintStack.widthAnchor).isActive = true
        guard let link else { return }
        let title = String(localized: "Open the Manufacturer’s Driver Page")
        let button = NSButton(title: title, target: self, action: #selector(openHintLink(_:)))
        button.isBordered = false
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue,
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
        ])
        button.tag = hintLinks.count
        button.toolTip = link.absoluteString
        hintLinks.append(link)
        hintStack.addArrangedSubview(button)
    }

    static func text(for message: DeviceHint.Message, device: String) -> String {
        switch message {
        case .useUSBInsteadOfBluetooth:
            String(localized: "The \(device) cannot be read reliably over Bluetooth. Connect it with the USB cable and choose its USB port.")
        case .pairInSystemSettings:
            String(localized: "Pair the \(device) in System Settings > Bluetooth first. myTracks Loader then connects to it by itself.")
        case .connectDirectlyViaUSB:
            String(localized: "Connect the logger with its USB cable. No port needs to be chosen.")
        }
    }

    @objc private func openHintLink(_ sender: NSButton) {
        guard hintLinks.indices.contains(sender.tag) else { return }
        NSWorkspace.shared.open(hintLinks[sender.tag])
    }

    // MARK: - Ports (spec "Choose the port")

    private func reloadPorts() {
        visiblePorts = PortPresentation.list(ports: ports, for: selection.entry(in: entries))
        portPopup.removeAllItems()
        for item in visiblePorts {
            portPopup.addItem(withTitle: Self.title(for: item))
            portPopup.lastItem?.toolTip = item.port.path
        }
        if let index = visiblePorts.firstIndex(where: { $0.port.path == selection.portPath }) { portPopup.selectItem(at: index) }
        portPopup.toolTip = selection.portPath
    }

    static func title(for item: PresentedPort) -> String {
        switch item.label {
        case let .usb(product?, chip?): String(localized: "USB: \(product) (\(chip))")
        case let .usb(product?, nil): String(localized: "USB: \(product)")
        case let .usb(nil, chip?): String(localized: "USB serial (\(chip))")
        case .usb(nil, nil): String(localized: "USB: \(item.port.name)")
        case let .bluetooth(name): String(localized: "Bluetooth: \(name)")
        case let .other(name): name
        }
    }

    @objc private func deviceChanged(_ sender: NSPopUpButton) {
        selection.selectDevice(entries[max(sender.indexOfSelectedItem, 0)].id, entries: entries, ports: ports)
        AppLog.shared.log(.selection, "device \(selection.entryID ?? "-"), port \(selection.portPath ?? "-")")
        reloadPorts()
        update()
    }

    @objc private func portChanged(_ sender: NSPopUpButton) {
        guard visiblePorts.indices.contains(sender.indexOfSelectedItem) else { return }
        selection.portPath = visiblePorts[sender.indexOfSelectedItem].port.path
        portPopup.toolTip = selection.portPath
        AppLog.shared.log(.selection, "port \(selection.portPath ?? "-")")
        update()
    }

    // MARK: - Reading and erasing

    private var driver: ProtocolDriver? {
        guard let entry = selection.entry(in: entries) else { return nil }
        return ProtocolDriver(entry: entry, portPath: entry.needsPort ? selection.portPath : nil, hidFactory: hidFactory,
                              bluetoothFactory: bluetoothFactory)
    }

    /// Hints that are added to the message of a failed read (spec "Device hints", design D6).
    private var failureHints: [String] {
        let device = selection.entry(in: entries)?.name ?? ""
        return selection.failureHints(entries: entries, ports: ports).map { Self.text(for: $0, device: device) }
    }

    #if DEBUG
    /// Debug automation: selects a catalog entry and port, then reads or erases (erasing skips the confirmation
    /// sheet only if the session presenter does; here it uses the normal flow).
    func debugRun(entryID: String, portPath: String?, erase: Bool) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        devicePopup.selectItem(at: index)
        selection = DeviceSelection(entryID: entryID, portPath: portPath ?? selection.portPath)
        reloadPorts()
        guard let driver else { return }
        if erase {
            sessionPresenter.erase(with: driver)
        } else {
            sessionPresenter.read(with: driver, failureHints: failureHints)
        }
        update()
    }

    /// Debug automation: selects a catalog entry (and port) without starting anything.
    func debugSelect(entryID: String, portPath: String?) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        devicePopup.selectItem(at: index)
        selection.selectDevice(entryID, entries: entries, ports: ports)
        if let portPath { selection.portPath = portPath }
        reloadPorts()
        update()
    }
    #endif

    @objc func read(_ sender: Any?) {
        guard let driver, selection.canRead(entries: entries, isRunning: sessionPresenter.isRunning) else { return }
        sessionPresenter.read(with: driver, failureHints: failureHints)
        update()
    }

    @objc func erase(_ sender: Any?) {
        guard let driver, selection.canErase(entries: entries, isRunning: sessionPresenter.isRunning) else { return }
        sessionPresenter.erase(with: driver)
        update()
    }

    // MARK: - Sources (replaceable by the debug automation)

    private static func currentPorts() -> [SerialPortInfo] {
        #if DEBUG
        if let fake = DebugPorts.ports { return fake }
        #endif
        return SerialPortCatalog.currentPorts()
    }

    private static func currentUSBDevices() -> [USBDeviceInfo] {
        #if DEBUG
        if let fake = DebugPorts.usbDevices { return fake }
        #endif
        return USBDeviceCatalog.currentDevices()
    }
}

#if DEBUG
/// `-DebugPorts` and `-DebugUSBDevices`: a port list instead of the real one, to check names, order and hints
/// without hardware (task 3.1 of change device-ports-and-hints).
///
///     -DebugPorts "bt:/dev/cu.HOLUX_M-241-SPPSlave,usb:/dev/cu.usbserial-1410:067B:2303:USB-Serial Controller,sys:/dev/cu.debug-console"
///     -DebugUSBDevices "067B:2303,1A86:7523"
enum DebugPorts {
    static var ports: [SerialPortInfo]? {
        guard let text = UserDefaults.standard.string(forKey: "DebugPorts") else { return nil }
        return text.split(separator: ",").compactMap { spec in
            let parts = spec.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2 else { return nil }
            switch parts[0] {
            case "bt": return SerialPortInfo(path: parts[1], isBluetooth: true)
            case "usb" where parts.count >= 4:
                return SerialPortInfo(path: parts[1], usbVendorID: Int(parts[2], radix: 16), usbProductID: Int(parts[3], radix: 16),
                                      usbProductName: parts.count > 4 ? parts[4] : nil)
            default: return SerialPortInfo(path: parts[1])
            }
        }
    }

    static var usbDevices: [USBDeviceInfo]? {
        guard let text = UserDefaults.standard.string(forKey: "DebugUSBDevices") else { return nil }
        return text.split(separator: ",").compactMap { spec in
            let parts = spec.split(separator: ":").map { Int($0, radix: 16) }
            guard parts.count == 2, let vendor = parts[0], let product = parts[1] else { return nil }
            return USBDeviceInfo(vendorID: vendor, productID: product)
        }
    }
}
#endif
