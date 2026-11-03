import Foundation
import LoggerCore

/// Local storage of captures and the on/off setting (spec `diagnostic-capture`).
///
/// - The setting defaults to "off" and survives restarts (`UserDefaults`).
/// - Only the captures of the last `maximumCount` operations are kept.
public struct CaptureStore: Sendable {
    public static let enabledKey = "DiagnosticCaptureEnabled"
    public static let defaultMaximumCount = 10

    public let directory: URL
    public let maximumCount: Int
    /// `nil` = standard user defaults; otherwise the suite name (used by tests).
    private let defaultsSuiteName: String?

    public init(directory: URL = CaptureStore.defaultDirectory,
                defaultsSuiteName: String? = nil,
                maximumCount: Int = CaptureStore.defaultMaximumCount) {
        self.directory = directory
        self.defaultsSuiteName = defaultsSuiteName
        self.maximumCount = maximumCount
    }

    private var defaults: UserDefaults {
        defaultsSuiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// `~/Library/Application Support/gpsloader/Captures`
    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("gpsloader", isDirectory: true)
            .appendingPathComponent("Captures", isDirectory: true)
    }

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.enabledKey) }
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
