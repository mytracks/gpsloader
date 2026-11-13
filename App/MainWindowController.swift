import AppKit
import BluetoothTransport
import HIDTransport
import LoggerCore

@MainActor
final class MainWindowController: NSWindowController, NSMenuItemValidation {
    private(set) var sessionPresenter: SessionPresenter!
    private(set) var conversionPresenter: ConversionPresenter!
    private(set) var devicePanel: DevicePanel!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "gpsloader"
        window.minSize = NSSize(width: 520, height: 360)
        self.init(window: window)
        sessionPresenter = SessionPresenter(window: window)
        conversionPresenter = ConversionPresenter(window: window, sessionPresenter: sessionPresenter)
        devicePanel = DevicePanel(sessionPresenter: sessionPresenter)
        devicePanel.hidFactory = IOKitHIDConnectionFactory()
        devicePanel.bluetoothFactory = IOBluetoothTransportFactory()
        sessionPresenter.onRunningChange = { [weak self] in self?.devicePanel.update() }
        buildContent()
        window.center()
        window.setFrameAutosaveName("MainWindow")
    }

    private func buildContent() {
        let filesBox = NSBox()
        filesBox.title = String(localized: "Files")
        let filesText = NSTextField(wrappingLabelWithString: String(localized: "Convert files from memory cards or USB storage to GPX. Supported formats: \(ConversionPresenter.supportedFormatNames). You can also drag files onto this window."))
        filesText.textColor = .secondaryLabelColor
        let convertButton = NSButton(title: String(localized: "Convert Files…"), target: self, action: #selector(convertFiles(_:)))
        let filesStack = NSStackView(views: [filesText, convertButton])
        filesStack.orientation = .vertical
        filesStack.alignment = .leading
        filesStack.spacing = 8
        filesText.widthAnchor.constraint(equalTo: filesStack.widthAnchor).isActive = true
        filesBox.contentView = padded(filesStack, fillWidth: true)

        let deviceBox = NSBox()
        deviceBox.title = String(localized: "Device")
        deviceBox.contentView = padded(devicePanel.makeView(), fillWidth: true)

        var sections: [NSView] = [filesBox, deviceBox]
        #if DEBUG
        sections.append(makeDebugBox())
        #endif

        let stack = NSStackView(views: sections)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        for section in sections {
            section.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        }
        let dropView = FileDropView()
        dropView.acceptsDrops = { [weak self] in self?.conversionPresenter.isConverting == false }
        dropView.onDrop = { [weak self] urls in self?.conversionPresenter.convert(urls) }
        stack.translatesAutoresizingMaskIntoConstraints = false
        dropView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: dropView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: dropView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: dropView.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: dropView.bottomAnchor),
        ])
        window?.contentView = dropView
    }

    // MARK: - File conversion (spec `file-conversion`)

    @objc func convertFiles(_ sender: Any?) {
        conversionPresenter.chooseFiles()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(convertFiles(_:)) { return !conversionPresenter.isConverting }
        return true
    }

    #if DEBUG
    // MARK: - Debug tools (tasks 7.1 / 7.3)

    private let scenarioPopup = NSPopUpButton()
    private let erasePopup = NSPopUpButton()

    private func makeDebugBox() -> NSView {
        let box = NSBox()
        box.title = "Debug"

        scenarioPopup.addItems(withTitles: DemoDriver.Scenario.allCases.map(\.rawValue))
        erasePopup.addItems(withTitles: ["erase: supported", "erase: experimental", "erase: unsupported"])
        let readButton = NSButton(title: "Read Demo Logger", target: self, action: #selector(readDemo(_:)))
        let eraseButton = NSButton(title: "Erase Demo Logger…", target: self, action: #selector(eraseDemo(_:)))

        let demoRow = NSStackView(views: [scenarioPopup, erasePopup, readButton, eraseButton])
        let stack = NSStackView(views: [demoRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        box.contentView = padded(stack)
        return box
    }

    private var demoDriver: DemoDriver {
        let scenario = DemoDriver.Scenario.allCases[max(scenarioPopup.indexOfSelectedItem, 0)]
        let erase: EraseSupport = [.supported, .experimental, .unsupported][max(erasePopup.indexOfSelectedItem, 0)]
        return DemoDriver(scenario: scenario, erase: erase)
    }

    @objc private func readDemo(_ sender: Any?) {
        sessionPresenter.read(with: demoDriver)
    }

    @objc private func eraseDemo(_ sender: Any?) {
        sessionPresenter.erase(with: demoDriver)
    }

    #endif

    private func padded(_ view: NSView, fillWidth: Bool = false) -> NSView {
        let container = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        let trailing = fillWidth
            ? view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8)
            : view.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            trailing,
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
        return container
    }
}
