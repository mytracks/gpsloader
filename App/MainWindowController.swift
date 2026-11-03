import AppKit
import GPSBabelRuntime
import LoggerCore

@MainActor
final class MainWindowController: NSWindowController {
    private(set) var sessionPresenter: SessionPresenter!
    private let environmentView = EnvironmentStatusView()

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
        buildContent()
        window.center()
        window.setFrameAutosaveName("MainWindow")
        AppEnvironment.shared.observeStatus { [weak self] status in
            self?.environmentView.show(status)
        }
    }

    private func buildContent() {
        let deviceBox = NSBox()
        deviceBox.title = String(localized: "Device")
        let placeholder = NSTextField(wrappingLabelWithString: String(localized: "Device drivers will be added in upcoming versions."))
        placeholder.textColor = .secondaryLabelColor
        deviceBox.contentView = padded(placeholder)

        var sections: [NSView] = [environmentView, deviceBox]
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
        window?.contentView = stack
    }

    #if DEBUG
    // MARK: - Debug tools (tasks 7.1 / 7.3)

    private let scenarioPopup = NSPopUpButton()
    private let erasePopup = NSPopUpButton()
    private let statusPopup = NSPopUpButton()

    private func makeDebugBox() -> NSView {
        let box = NSBox()
        box.title = "Debug"

        scenarioPopup.addItems(withTitles: DemoDriver.Scenario.allCases.map(\.rawValue))
        erasePopup.addItems(withTitles: ["erase: supported", "erase: experimental", "erase: unsupported"])
        let readButton = NSButton(title: "Read Demo Logger", target: self, action: #selector(readDemo(_:)))
        let eraseButton = NSButton(title: "Erase Demo Logger…", target: self, action: #selector(eraseDemo(_:)))

        statusPopup.addItems(withTitles: ["status: real", "status: checking", "status: ready", "status: rosetta missing",
                                          "status: broken"])
        statusPopup.target = self
        statusPopup.action = #selector(simulateStatus(_:))

        let demoRow = NSStackView(views: [scenarioPopup, erasePopup, readButton, eraseButton])
        let statusRow = NSStackView(views: [statusPopup])
        let stack = NSStackView(views: [demoRow, statusRow])
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

    @objc private func simulateStatus(_ sender: NSPopUpButton) {
        let statuses: [GPSBabelStatus?] = [nil, .checking, .ready(version: "1.7.0"), .rosettaMissing,
                                           .broken(reason: "Simulated: dyld: Library not loaded: QtCoreGpsBabel")]
        AppEnvironment.shared.simulatedStatus = statuses[sender.indexOfSelectedItem]
    }
    #endif

    private func padded(_ view: NSView) -> NSView {
        let container = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            view.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
        return container
    }
}

/// "Umgebung" section: gpsbabel/Rosetta status with action (spec `app-shell`, "Umgebungsstatus im Hauptfenster").
@MainActor
final class EnvironmentStatusView: NSBox {
    private let symbol = NSTextField(labelWithString: "")
    private let headline = NSTextField(labelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let spinner = NSProgressIndicator()
    private let actionButton = NSButton(title: "", target: nil, action: nil)
    private let recheckButton = NSButton(title: "", target: nil, action: nil)

    init() {
        super.init(frame: .zero)
        title = String(localized: "Environment")
        headline.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        symbol.font = .systemFont(ofSize: 20)
        detail.textColor = .secondaryLabelColor
        detail.isSelectable = true
        spinner.style = .spinning
        spinner.controlSize = .small
        actionButton.title = String(localized: "Install Rosetta…")
        actionButton.target = self
        actionButton.action = #selector(installRosetta(_:))
        recheckButton.title = String(localized: "Check Again")
        recheckButton.target = self
        recheckButton.action = #selector(recheck(_:))

        let headlineRow = NSStackView(views: [symbol, spinner, headline])
        headlineRow.spacing = 8
        let buttons = NSStackView(views: [actionButton, recheckButton])
        let stack = NSStackView(views: [headlineRow, detail, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            detail.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        contentView = container
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(_ status: GPSBabelStatus) {
        spinner.isHidden = true
        spinner.stopAnimation(nil)
        symbol.isHidden = false
        actionButton.isHidden = true
        recheckButton.isHidden = false

        switch status {
        case .checking:
            symbol.isHidden = true
            spinner.isHidden = false
            spinner.startAnimation(nil)
            headline.stringValue = String(localized: "Checking gpsbabel…")
            detail.stringValue = String(localized: "The first start under Rosetta can take a few seconds.")
            recheckButton.isHidden = true
        case let .ready(version):
            symbol.stringValue = "✅"
            headline.stringValue = String(localized: "Ready – gpsbabel \(version)")
            detail.stringValue = String(localized: "All supported devices can be used.")
        case .rosettaMissing:
            symbol.stringValue = "⚠️"
            headline.stringValue = String(localized: "Rosetta is not installed")
            detail.stringValue = String(localized: "Devices that use gpsbabel only work after Rosetta has been installed. Devices with built-in drivers work without Rosetta.")
            actionButton.isHidden = false
        case let .broken(reason):
            symbol.stringValue = "❌"
            headline.stringValue = String(localized: "gpsbabel cannot be started")
            detail.stringValue = reason
        }
    }

    @objc private func installRosetta(_ sender: Any?) {
        RosettaInstallation.shared.start(presentingWindow: window)
    }

    @objc private func recheck(_ sender: Any?) {
        AppEnvironment.shared.refreshRuntime()
    }
}
