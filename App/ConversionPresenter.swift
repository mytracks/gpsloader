import AppKit
import FileConversion
import GPSLoggerKit
import GPXExport
import LoggerCore
import SupportPackage
import UniformTypeIdentifiers

/// Converts files of the formats in the app catalog (GPSLoggerKit and GPSLoggerKitGPL) into one GPX file (spec `file-conversion`):
/// choose → detect → ask about unrecognized files → read with progress → save → show warnings.
@MainActor
final class ConversionPresenter {
    private weak var window: NSWindow?
    private let sessionPresenter: SessionPresenter
    private var task: Task<Void, Never>?
    private var progress: ProgressSheetController?
    /// The question about unrecognized files while it is shown; closed by `cancel()`.
    private var pendingQuestion: NSAlert?

    init(window: NSWindow, sessionPresenter: SessionPresenter) {
        self.window = window
        self.sessionPresenter = sessionPresenter
    }

    /// `true` while a conversion runs; a second one is not started (spec "Progress and cancellation").
    private(set) var isConverting = false

    /// Names of the supported formats for the main window, e.g. "NMEA 0183, GPX, IGC (flight recorder)".
    static var supportedFormatNames: String {
        ListFormatter.localizedString(byJoining: AppFormats.catalog.all.map(\.displayName))
    }

    // MARK: - Choosing files

    /// Spec "Choose files": an open panel for one or more files of any type.
    func chooseFiles() {
        guard !isConverting else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = String(localized: "Convert")
        panel.message = String(localized: "Choose one or more files to convert to GPX.")
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            self.convert(panel.urls)
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: handle) } else { handle(panel.runModal()) }
    }

    /// Converts the given files (from the open panel, drag & drop or debug automation).
    func convert(_ urls: [URL]) {
        guard !isConverting, !urls.isEmpty else { return }
        AppLog.shared.log(.conversion, "start \(urls.count) files")
        isConverting = true
        showProgress()
        task = Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<ConversionPlan, Error> in
                Result { try FileConverter.plan(for: urls) }
            }.value
            switch outcome {
            case .success(let plan):
                await self.continueConversion(plan, urls: urls)
            case .failure(let error):
                self.finish()
                self.present(error)
            }
        }
    }

    /// Cancels a running conversion (e.g. when the app quits).
    func cancel() {
        task?.cancel()
        if let question = pendingQuestion, let sheet = question.window.sheetParent {
            sheet.endSheet(question.window, returnCode: .alertSecondButtonReturn)
        }
    }

    // MARK: - Steps

    private func continueConversion(_ plan: ConversionPlan, urls: [URL]) async {
        if Task.isCancelled { return finish() }
        if plan.isEmpty {
            finish()
            return showMessage(String(localized: "The format of the chosen files is not supported."),
                               detail: plan.unrecognized.joined(separator: "\n"))
        }
        AppLog.shared.log(.conversion, "formats \(plan.groups.map { "\($0.formatID.rawValue)×\($0.inputs.count)" }.joined(separator: ", ")), "
            + "\(plan.unrecognized.count) unrecognized")
        var plan = plan
        let skipped = plan.unrecognized
        if !skipped.isEmpty {
            hideProgress()
            guard await confirmSkipping(plan.unrecognized) else { return finish() }
            plan = plan.excludingUnrecognized()
            showProgress()
        }
        let conversion = Task.detached(priority: .userInitiated) { try await FileConverter.convert(plan) }
        let result = await withTaskCancellationHandler {
            await conversion.result
        } onCancel: {
            conversion.cancel()
        }
        finish()
        switch result {
        case .success(let imported):
            AppLog.shared.log(.conversion, "converted: \(imported.recording.tracks.count) tracks, "
                + "\(imported.recording.trackPointCount) points, \(imported.recording.waypoints.count) waypoints, \(imported.warnings.count) warnings")
            let recognized = urls.filter { !skipped.contains($0.lastPathComponent) }
            save(imported, suggestedName: FileConverter.suggestedFileName(for: recognized.isEmpty ? urls : recognized),
                 directory: urls.first?.deletingLastPathComponent())
        case .failure(let error):
            present(error)
        }
    }

    /// Spec "Unrecognized files".
    private func confirmSkipping(_ names: [String]) async -> Bool {
        let alert = NSAlert()
        alert.messageText = names.count == 1
            ? String(localized: "The format of “\(names[0])” is not supported.")
            : String(localized: "The format of \(names.count) files is not supported.")
        alert.informativeText = names.count == 1 ? "" : names.joined(separator: "\n")
        alert.addButton(withTitle: names.count == 1 ? String(localized: "Continue Without This File")
                                                    : String(localized: "Continue Without These Files"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        pendingQuestion = alert
        return await withCheckedContinuation { continuation in
            let handle: (NSApplication.ModalResponse) -> Void = { response in
                self.pendingQuestion = nil
                continuation.resume(returning: response == .alertFirstButtonReturn && !Task.isCancelled)
            }
            if let window { alert.beginSheetModal(for: window, completionHandler: handle) } else { handle(alert.runModal()) }
        }
    }

    /// Spec "Save"; afterwards the warnings (spec "Errors and warnings").
    private func save(_ result: ImportResult, suggestedName: String, directory: URL?) {
        let write: (URL) -> Void = { url in
            do {
                try GPXExport.write(result.recording, to: url, creator: AppEnvironment.shared.gpxCreator)
            } catch let error as LoggerError {
                return self.sessionPresenter.showError(error)
            } catch {
                return self.sessionPresenter.showError(LoggerError(.writeFailed, detail: error.localizedDescription))
            }
            self.showWarnings(result.warnings)
        }
        #if DEBUG
        // Debug automation: write without the (out-of-process) save panel.
        if let path = UserDefaults.standard.string(forKey: "DebugSaveDirectory") {
            try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            return write(URL(fileURLWithPath: path).appendingPathComponent(suggestedName))
        }
        #endif
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "gpx") ?? .xml]
        panel.nameFieldStringValue = suggestedName
        panel.isExtensionHidden = false
        if let directory { panel.directoryURL = directory }
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            write(url)
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: handle) } else { handle(panel.runModal()) }
    }

    private func showWarnings(_ warnings: [ImportWarning]) {
        guard !warnings.isEmpty else { return }
        showMessage(String(localized: "The GPX file has been saved. Some data was skipped:"),
                    detail: warnings.map { "• " + $0.message() }.joined(separator: "\n"), style: .informational)
    }

    // MARK: - Errors and messages

    private func present(_ error: Error) {
        if error is CancellationError { return AppLog.shared.log(.conversion, "cancelled") }
        AppLog.shared.log(.error, "conversion failed: \((error as? GPSLoggerError)?.kind.key ?? String(describing: type(of: error)))")
        if let error = error as? GPSLoggerError {
            let detail = error.failureReason.map { String(localized: "Details: \($0)") } ?? ""
            return showMessage(error.errorDescription ?? error.kind.key, detail: detail)
        }
        showMessage(error.localizedDescription, detail: "")
    }

    private func showMessage(_ message: String, detail: String, style: NSAlert.Style = .warning) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = message
        alert.informativeText = detail
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    // MARK: - Progress

    private func showProgress() {
        let sheet = ProgressSheetController(title: String(localized: "Converting files…")) { [weak self] in
            self?.cancel()
        }
        progress = sheet
        // A child window, as for logger sessions: a sheet would block quitting.
        if let window, let progressWindow = sheet.window {
            let size = progressWindow.frame.size
            let parent = window.frame
            progressWindow.setFrameOrigin(NSPoint(x: parent.midX - size.width / 2, y: parent.maxY - size.height - 60))
            window.addChildWindow(progressWindow, ordered: .above)
            progressWindow.makeKeyAndOrderFront(nil)
        }
    }

    private func hideProgress() {
        if let progressWindow = progress?.window {
            window?.removeChildWindow(progressWindow)
            progressWindow.orderOut(nil)
        }
        progress = nil
    }

    private func finish() {
        hideProgress()
        isConverting = false
        task = nil
    }
}

/// Main window content view that accepts files dropped from the Finder (spec "Choose files").
@MainActor
final class FileDropView: NSView {
    /// Called with the dropped regular files.
    var onDrop: (([URL]) -> Void)?
    /// Drops are refused while this returns `false`.
    var acceptsDrops: () -> Bool = { true }
    /// Called with `true` while acceptable files are dragged over the window (highlights the drop zone).
    var onDragHighlight: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Only regular files; folders are refused.
    static func regularFiles(in pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                          options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return [] }
        let regular = urls.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        return regular.count == urls.count ? regular : []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepted = acceptsDrops() && !Self.regularFiles(in: sender.draggingPasteboard).isEmpty
        onDragHighlight?(accepted)
        return accepted ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragHighlight?(false)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDragHighlight?(false)
        let urls = Self.regularFiles(in: sender.draggingPasteboard)
        guard acceptsDrops(), !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
}
