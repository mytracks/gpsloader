import AppKit
import DiagnosticCapture
import GPSLoggerKit
import GPXExport
import LoggerCore
import SupportPackage
import UniformTypeIdentifiers

/// Runs read/erase operations for a driver and presents progress, results and errors
/// (spec `logger-session`).
@MainActor
final class SessionPresenter {
    private weak var window: NSWindow?
    private var progressSheet: ProgressSheetController?
    private(set) var runningSessions: [LoggerSession] = [] {
        didSet { onRunningChange?() }
    }
    /// Called when a session starts or ends (the device panel updates its buttons).
    var onRunningChange: (() -> Void)?

    init(window: NSWindow) {
        self.window = window
    }

    var isRunning: Bool { !runningSessions.isEmpty }

    // MARK: - Reading

    /// `failureHints` are added to the message when reading fails (spec `device-mode`,
    /// "Device hints"), e.g. "use USB instead of Bluetooth".
    func read(with driver: any LoggerDriver, failureHints: [String] = []) {
        let (session, capture) = makeSession(driver)
        Task {
            let outcome = await run(session, title: String(localized: "Reading \(driver.descriptor.name)…")) {
                await session.read()
            }
            capture.finish()
            await self.present(outcome, driver: driver, failureHints: failureHints)
        }
    }

    // MARK: - Erasing

    func erase(with driver: any LoggerDriver) {
        let descriptor = driver.descriptor
        guard descriptor.eraseSupport != .unsupported else {
            // The UI does not offer erasing for such drivers; this is a safety net.
            showMessage(String(localized: "Erasing is not supported for this device."))
            return
        }
        confirmErase(descriptor) { confirmation in
            guard let confirmation else { return }
            let (session, capture) = self.makeSession(driver)
            Task {
                let outcome = await self.run(session, title: String(localized: "Erasing \(descriptor.name)…")) {
                    await session.erase(confirmation)
                }
                capture.finish()
                await self.present(outcome, driver: driver)
            }
        }
    }

    /// Spec "Confirmation before erasing" (with the warning for experimental drivers).
    private func confirmErase(_ descriptor: DriverDescriptor, completion: @escaping (EraseConfirmation?) -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(localized: "Erase all data on \(descriptor.name)?")
        var text = String(localized: "Erased data cannot be recovered. Save the data first if you still need it.")
        let experimental = descriptor.eraseSupport == .experimental
        if experimental {
            text += "\n\n" + String(localized: "Warning: Erasing is experimental for this device. It has not been tested with a real device and might fail or leave the logger in an unusable state.")
        }
        alert.informativeText = text
        alert.addButton(withTitle: String(localized: "Erase"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else {
                completion(nil)
                return
            }
            completion(.confirmedByUser(acknowledgingExperimentalErase: experimental))
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: handle) } else { handle(alert.runModal()) }
    }

    // MARK: - Session plumbing

    private func makeSession(_ driver: any LoggerDriver) -> (LoggerSession, OperationCapture) {
        AppLog.shared.log(.operation, "start \(driver.descriptor.id) (\(driver.descriptor.name)) on \(driver.resourceKey)")
        let environment = AppEnvironment.shared
        let capture = environment.makeCapture(header: DiagnosticHeader(driver: driver.descriptor.id, port: driver.resourceKey))
        let session = LoggerSession(driver: driver, reservations: environment.reservations, diagnostics: capture.recorder)
        return (session, capture)
    }

    private func run(_ session: LoggerSession, title: String,
                     operation: @escaping @Sendable () async -> SessionOutcome) async -> SessionOutcome {
        runningSessions.append(session)
        let sheet = ProgressSheetController(title: title) { session.cancel() }
        progressSheet = sheet
        // A child window instead of a sheet: AppKit refuses to quit while a sheet is shown, which would block
        // quitting (and logout) during an operation.
        if let window, let progressWindow = sheet.window {
            let size = progressWindow.frame.size
            let parent = window.frame
            progressWindow.setFrameOrigin(NSPoint(x: parent.midX - size.width / 2,
                                                  y: parent.maxY - size.height - 60))
            window.addChildWindow(progressWindow, ordered: .above)
            progressWindow.makeKeyAndOrderFront(nil)
        }

        let events = Task { @MainActor in
            for await event in session.events {
                if case let .progress(update) = event { sheet.update(update) }
                if case .finished = event { break }
            }
        }
        let outcome = await operation()
        events.cancel()

        if let progressWindow = sheet.window {
            window?.removeChildWindow(progressWindow)
            progressWindow.orderOut(nil)
        }
        progressSheet = nil
        runningSessions.removeAll { $0 === session }
        return outcome
    }

    // MARK: - Results

    private func present(_ outcome: SessionOutcome, driver: any LoggerDriver, failureHints: [String] = []) async {
        AppLog.shared.log(outcome.isFailure ? .error : .operation,
                          "end \(driver.descriptor.id) on \(driver.resourceKey): \(outcome.logDescription)")
        switch outcome {
        case let .recording(recording):
            save(recording, device: driver.descriptor.name)
        case .emptyDevice:
            showMessage(String(localized: "The logger does not contain any data."))
        case .erased:
            showMessage(String(localized: "The data has been erased."))
        case let .failed(error):
            showError(error, offerSupportPackage: true, hints: failureHints)
        case .cancelled:
            break
        case let .rejected(reason):
            switch reason {
            case let .busy(resource):
                showMessage(String(localized: "Another operation is already using \(resource). Wait until it has finished."))
            case .eraseNotSupported:
                showMessage(String(localized: "Erasing is not supported for this device."))
            case .experimentalNotAcknowledged:
                showMessage(String(localized: "Erasing was not confirmed."))
            }
        }
    }

    /// Spec "Save the result".
    private func save(_ recording: Recording, device: String) {
        let suggestedName = GPXFileName.suggested(device: device, date: Date())
        #if DEBUG
        // Debug automation: write without the (out-of-process) save panel.
        if let directory = UserDefaults.standard.string(forKey: "DebugSaveDirectory") {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(suggestedName)
            do {
                try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                try GPXExport.write(recording, to: url, creator: AppEnvironment.shared.gpxCreator)
            } catch {
                showError(error as? LoggerError ?? LoggerError(.writeFailed, detail: error.localizedDescription))
            }
            return
        }
        #endif
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "gpx") ?? .xml]
        panel.nameFieldStringValue = suggestedName
        panel.isExtensionHidden = false
        let write: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try GPXExport.write(recording, to: url, creator: AppEnvironment.shared.gpxCreator)
            } catch let error as LoggerError {
                self.showError(error)
            } catch {
                self.showError(LoggerError(.writeFailed, detail: error.localizedDescription))
            }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: write) } else { write(panel.runModal()) }
    }

    /// Spec "Einheitliche Fehlermeldungen": message, hint and technical detail. Failed operations also offer
    /// "Create Support Package…" (spec `support-package`, "Create a support package").
    func showError(_ error: LoggerError, offerSupportPackage: Bool = false, hints: [String] = []) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = error.errorDescription ?? error.kind.rawValue
        var text = (hints + [error.recoverySuggestion].compactMap { $0 }).joined(separator: "\n\n")
        if !error.detail.isEmpty {
            text += (text.isEmpty ? "" : "\n\n") + String(localized: "Details: \(error.detail)")
        }
        alert.informativeText = text
        guard offerSupportPackage else {
            if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            return
        }
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Create Support Package…"))
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertSecondButtonReturn else { return }
            DispatchQueue.main.async { SupportPackageController.shared.createSupportPackage(nil) }
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: handle) } else { handle(alert.runModal()) }
    }

    private func showMessage(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
}

/// Progress window (child of the main window) with a progress indicator, the current step and a Cancel button (spec "Progress", "Cancellation").
@MainActor
final class ProgressSheetController: NSWindowController {
    /// Two indicators instead of switching one between modes: after an animated indeterminate phase,
    /// a switched indicator does not draw its determinate value correctly.
    private let indeterminateIndicator = NSProgressIndicator()
    private let determinateIndicator = NSProgressIndicator()
    private let stepLabel = NSTextField(labelWithString: "")
    private let onCancel: () -> Void

    init(title: String, onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 130),
                              styleMask: [.titled], backing: .buffered, defer: false)
        super.init(window: window)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        indeterminateIndicator.style = .bar
        indeterminateIndicator.isIndeterminate = true
        indeterminateIndicator.startAnimation(nil)
        determinateIndicator.style = .bar
        determinateIndicator.isIndeterminate = false
        determinateIndicator.minValue = 0
        determinateIndicator.maxValue = 1
        determinateIndicator.isHidden = true
        stepLabel.textColor = .secondaryLabelColor
        stepLabel.lineBreakMode = .byTruncatingTail
        let cancelButton = NSButton(title: String(localized: "Cancel"), target: self, action: #selector(cancel(_:)))
        cancelButton.keyEquivalent = "\u{1b}"

        let stack = NSStackView(views: [titleLabel, indeterminateIndicator, determinateIndicator, stepLabel, cancelButton])
        stack.detachesHiddenViews = true
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.setCustomSpacing(16, after: stepLabel)
        for indicator in [indeterminateIndicator, determinateIndicator] {
            indicator.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        }
        cancelButton.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        window.contentView = stack
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(_ update: ProgressUpdate) {
        let determinate = update.fraction != nil
        determinateIndicator.isHidden = !determinate
        indeterminateIndicator.isHidden = determinate
        if determinate {
            indeterminateIndicator.stopAnimation(nil)
        } else {
            indeterminateIndicator.startAnimation(nil)
        }

        if case let .determinate(completed, total, step) = update, let fraction = update.fraction {
            determinateIndicator.doubleValue = fraction
            let amount = String(localized: "\(completed) of \(total)")
            stepLabel.stringValue = step.map { "\($0) – \(amount)" } ?? amount
        } else {
            stepLabel.stringValue = update.step ?? ""
        }
    }

    @objc private func cancel(_ sender: Any?) {
        stepLabel.stringValue = String(localized: "Cancelling…")
        (sender as? NSButton)?.isEnabled = false
        onCancel()
    }
}

extension SessionOutcome {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    /// One line for the app log; no positions.
    var logDescription: String {
        switch self {
        case let .recording(recording):
            return "\(recording.tracks.count) tracks, \(recording.trackPointCount) points, \(recording.waypoints.count) waypoints"
        case .emptyDevice: return "empty"
        case .erased: return "erased"
        case let .failed(error): return "failed (\(error.kind.rawValue)) \(error.detail)"
        case .cancelled: return "cancelled"
        case let .rejected(reason): return "rejected (\(reason))"
        }
    }
}
