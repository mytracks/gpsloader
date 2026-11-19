import AppKit
import BluetoothTransport
import HIDTransport
import LoggerCore

/// The two sections of the main window (spec `app-shell`, "Sections of the main window").
enum MainWindowSection: String, CaseIterable {
    case files, device

    static let defaultsKey = "MainWindowSection"

    /// The last section, or "device" on the first start.
    static var stored: MainWindowSection {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(MainWindowSection.init(rawValue:)) ?? .device
    }

    var title: String {
        switch self {
        case .files: String(localized: "Convert Files")
        case .device: String(localized: "Read Device")
        }
    }
}

@MainActor
final class MainWindowController: NSWindowController, NSMenuItemValidation, NSToolbarDelegate {
    private(set) var sessionPresenter: SessionPresenter!
    private(set) var conversionPresenter: ConversionPresenter!
    private(set) var devicePanel: DevicePanel!

    private let tabView = NSTabView()
    private var sectionGroup: NSToolbarItemGroup?
    private let dropZone = DropZoneView()
    private(set) var section: MainWindowSection = .device

    private static let toolbarIdentifier = NSToolbar.Identifier("MainToolbar")
    private static let sectionItemIdentifier = NSToolbarItem.Identifier("Section")

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 440),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppName.current
        window.minSize = NSSize(width: 520, height: 360)
        self.init(window: window)
        sessionPresenter = SessionPresenter(window: window)
        conversionPresenter = ConversionPresenter(window: window, sessionPresenter: sessionPresenter)
        devicePanel = DevicePanel(sessionPresenter: sessionPresenter)
        devicePanel.hidFactory = IOKitHIDConnectionFactory()
        devicePanel.bluetoothFactory = IOBluetoothTransportFactory()
        sessionPresenter.onRunningChange = { [weak self] in self?.devicePanel.update() }
        buildToolbar()
        buildContent()
        select(MainWindowSection.stored)
        window.center()
        window.setFrameAutosaveName("MainWindow")
    }

    // MARK: - Sections (design D1, D2)

    private func buildToolbar() {
        guard let window else { return }
        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        if #available(macOS 13.0, *) { toolbar.centeredItemIdentifier = Self.sectionItemIdentifier }
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.sectionItemIdentifier, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == Self.sectionItemIdentifier else { return nil }
        let titles = MainWindowSection.allCases.map(\.title)
        let group = NSToolbarItemGroup(itemIdentifier: itemIdentifier, titles: titles, selectionMode: .selectOne,
                                       labels: titles, target: self, action: #selector(sectionChosen(_:)))
        group.label = String(localized: "Section")
        group.selectedIndex = MainWindowSection.allCases.firstIndex(of: section) ?? 0
        sectionGroup = group
        return group
    }

    @objc private func sectionChosen(_ sender: NSToolbarItemGroup) {
        guard MainWindowSection.allCases.indices.contains(sender.selectedIndex) else { return }
        select(MainWindowSection.allCases[sender.selectedIndex])
    }

    /// Shows a section and remembers it (scenarios "Remember the section", "Keyboard shortcut").
    func select(_ section: MainWindowSection) {
        self.section = section
        tabView.selectTabViewItem(withIdentifier: section.rawValue)
        sectionGroup?.selectedIndex = MainWindowSection.allCases.firstIndex(of: section) ?? 0
        UserDefaults.standard.set(section.rawValue, forKey: MainWindowSection.defaultsKey)
    }

    @objc func showFilesSection(_ sender: Any?) { select(.files) }
    @objc func showDeviceSection(_ sender: Any?) { select(.device) }

    // MARK: - Content

    private func buildContent() {
        tabView.tabViewType = .noTabsNoBorder
        tabView.drawsBackground = false
        let filesItem = NSTabViewItem(identifier: MainWindowSection.files.rawValue)
        filesItem.view = padded(makeFilesSection())
        let deviceItem = NSTabViewItem(identifier: MainWindowSection.device.rawValue)
        deviceItem.view = padded(devicePanel.makeView(), alignTop: true)
        tabView.addTabViewItem(filesItem)
        tabView.addTabViewItem(deviceItem)

        var sections: [NSView] = [tabView]
        #if DEBUG
        sections.append(makeDebugBox())
        #endif
        let stack = NSStackView(views: sections)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 16, right: 12)
        for view in sections {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24).isActive = true
        }
        tabView.setContentHuggingPriority(.defaultLow, for: .vertical)

        // Drops are accepted in both sections and switch to "Convert Files" (spec `file-conversion`, "Choose files").
        let dropView = FileDropView()
        dropView.acceptsDrops = { [weak self] in self?.conversionPresenter.isConverting == false }
        dropView.onDragHighlight = { [weak self] highlighted in self?.dropZone.isHighlighted = highlighted }
        dropView.onDrop = { [weak self] urls in self?.convertDropped(urls) }
        stack.translatesAutoresizingMaskIntoConstraints = false
        dropView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: dropView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: dropView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: dropView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: dropView.bottomAnchor),
        ])
        window?.contentView = dropView
    }

    /// Design D3: drop zone, "Choose Files…" and the supported formats.
    private func makeFilesSection() -> NSView {
        dropZone.onClick = { [weak self] in self?.convertFiles(nil) }
        let chooseButton = NSButton(title: String(localized: "Choose Files…"), target: self, action: #selector(convertFiles(_:)))
        chooseButton.keyEquivalent = "\r"
        let formats = NSTextField(wrappingLabelWithString: String(localized: "Files from memory cards or USB storage are converted to one GPX file. Supported formats: \(ConversionPresenter.supportedFormatNames)."))
        formats.textColor = .secondaryLabelColor
        formats.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let stack = NSStackView(views: [dropZone, chooseButton, formats])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        dropZone.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        dropZone.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        formats.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    // MARK: - File conversion (spec `file-conversion`)

    @objc func convertFiles(_ sender: Any?) {
        select(.files)
        conversionPresenter.chooseFiles()
    }

    /// Dropped files and the debug automation (`-DebugConvert`): switch to "Convert Files", then convert.
    func convertDropped(_ urls: [URL]) {
        select(.files)
        conversionPresenter.convert(urls)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(convertFiles(_:)):
            return !conversionPresenter.isConverting
        case #selector(showFilesSection(_:)):
            menuItem.state = section == .files ? .on : .off
            return true
        case #selector(showDeviceSection(_:)):
            menuItem.state = section == .device ? .on : .off
            return true
        default:
            return true
        }
    }

    #if DEBUG
    // MARK: - Debug tools (design D4: below both sections)

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

    private func padded(_ view: NSView, alignTop: Bool = false) -> NSView {
        let container = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        var constraints = [
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
        ]
        constraints.append(alignTop
            ? view.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -8)
            : view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8))
        NSLayoutConstraint.activate(constraints)
        return container
    }
}

/// The drop zone of the "Convert Files" section (design D3): dashed frame, symbol and text; highlighted while
/// files are dragged over the window; a click opens the open panel.
@MainActor
final class DropZoneView: NSView {
    var onClick: (() -> Void)?
    var isHighlighted = false {
        didSet { needsDisplay = true }
    }

    private let label = NSTextField(labelWithString: String(localized: "Drag Files Here"))
    private let icon = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        if #available(macOS 11.0, *),
           let image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil) {
            icon.image = image
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 32, weight: .regular)
        }
        icon.contentTintColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: NSFont.systemFontSize + 2)
        label.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [icon, label])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityRole(.button)
        setAccessibilityLabel(label.stringValue)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 10, yRadius: 10)
        path.lineWidth = isHighlighted ? 3 : 1.5
        path.setLineDash(isHighlighted ? [] : [6, 4], count: isHighlighted ? 0 : 2, phase: 0)
        (isHighlighted ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).setStroke()
        if isHighlighted {
            NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
            path.fill()
        }
        path.stroke()
    }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}
