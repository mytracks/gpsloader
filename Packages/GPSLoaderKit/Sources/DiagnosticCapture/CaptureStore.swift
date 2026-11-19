import Foundation
import LoggerCore

/// Local storage of captures (spec `diagnostic-capture`). Every operation is recorded ("Aufzeichnung immer
/// aktiv"); only the captures of the last `maximumCount` operations are kept.
public struct CaptureStore: Sendable {
    public static let defaultMaximumCount = 10

    public let directory: URL
    public let maximumCount: Int

    public init(directory: URL = CaptureStore.defaultDirectory,
                maximumCount: Int = CaptureStore.defaultMaximumCount) {
        self.directory = directory
        self.maximumCount = maximumCount
    }

    /// `~/Library/Application Support/myTracks Loader/Captures`
    public static var defaultDirectory: URL {
        supportFolder(named: ProductName.name).appendingPathComponent("Captures", isDirectory: true)
    }

    /// The app's folder in Application Support (`myTracks Loader`).
    public static var supportDirectory: URL { supportFolder(named: ProductName.name) }

    /// `~/Library/Application Support/gpsloader` of earlier builds, moved by `LegacyFolderMigration` at start.
    public static var legacySupportDirectory: URL { supportFolder(named: ProductName.legacyName) }

    private static func supportFolder(named name: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(name, isDirectory: true)
    }

    /// Stores a finished capture and removes the oldest ones beyond `maximumCount`.
    @discardableResult
    public func save(_ recorder: CaptureRecorder) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName(for: recorder))
        try recorder.encoded().write(to: url, options: .atomic)
        try prune()
        return url
    }

    /// All stored captures, oldest first.
    public func captures() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.pathExtension == CaptureFormat.fileExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// The most recent capture, if any.
    public func latest() -> URL? {
        captures().last
    }

    private func prune() throws {
        let all = captures()
        guard all.count > maximumCount else { return }
        for url in all.prefix(all.count - maximumCount) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Sortable, unique file name: capture-20261102-143005-123-<driver>-<random>.jsonl
    private func fileName(for recorder: CaptureRecorder) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond],
                                        from: recorder.startDate)
        let stamp = String(format: "%04d%02d%02d-%02d%02d%02d-%03d",
                           c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0,
                           (c.nanosecond ?? 0) / 1_000_000)
        let driver = (recorder.driverName ?? "session")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let random = UUID().uuidString.prefix(6)
        return "capture-\(stamp)-\(driver)-\(random).\(CaptureFormat.fileExtension)"
    }
}

/// The capture of one operation: the recorder gets the header at once, `finish()` stores it whatever the
/// outcome of the operation was (spec `diagnostic-capture`, "Capture always on").
public struct OperationCapture: Sendable {
    public let recorder: CaptureRecorder
    public let store: CaptureStore

    public init(store: CaptureStore, environment: CaptureEnvironment, header: DiagnosticHeader) {
        self.store = store
        recorder = CaptureRecorder(environment: environment)
        recorder.record(.header(header))
    }

    /// Stores the capture; `nil` if it could not be written.
    @discardableResult
    public func finish() -> URL? {
        try? store.save(recorder)
    }
}
