import Foundation
import LoggerCore
import os

/// The app's own log (spec `support-package`, "App-Protokoll"): one line per entry in
/// `~/Library/Logs/myTracks Loader/myTracks Loader.log`, also sent to the unified log for Console.app.
///
/// When the file would grow beyond `maximumFileSize`, it is renamed to `myTracks Loader.1.log` (older ones move up
/// one number) and a new file starts; at most `maximumFileCount` files are kept. Callers must not pass
/// positions or file names.
public final class AppLog: Sendable {
    public enum Category: String, Sendable {
        case app, ports, selection, operation, conversion, error
    }

    public static let shared = AppLog()

    /// `~/Library/Logs/myTracks Loader`
    public static var defaultDirectory: URL { logsDirectory(named: ProductName.name) }

    /// `~/Library/Logs/gpsloader` of earlier builds, moved by `LegacyFolderMigration` at start.
    public static var legacyDirectory: URL { logsDirectory(named: ProductName.legacyName) }

    private static func logsDirectory(named name: String) -> URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return library.appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    public let directory: URL
    public let maximumFileSize: Int
    public let maximumFileCount: Int
    private let now: @Sendable () -> Date
    private let lock = Locked<Void>(())
    private let unified = os.Logger(subsystem: "info.stichling.gpsloader", category: "app")

    public init(directory: URL = AppLog.defaultDirectory, maximumFileSize: Int = 1_000_000, maximumFileCount: Int = 5,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.maximumFileSize = maximumFileSize
        self.maximumFileCount = max(maximumFileCount, 1)
        self.now = now
    }

    /// The current file.
    public var currentFile: URL { file(0) }

    /// All existing log files, oldest first.
    public var files: [URL] {
        (0..<maximumFileCount).reversed().map(file).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Gives log files of earlier builds ("gpsloader.log", "gpsloader.N.log") the current names, as files older
    /// than the existing ones, so that rotation and the support package include them. Files beyond
    /// `maximumFileCount` are removed, as rotation would. Call once at start, before logging.
    public func adoptLegacyFiles() {
        let manager = FileManager.default
        func legacy(_ index: Int) -> URL {
            directory.appendingPathComponent(index == 0 ? "\(ProductName.legacyName).log" : "\(ProductName.legacyName).\(index).log")
        }
        let old = (0..<maximumFileCount).map(legacy).filter { manager.fileExists(atPath: $0.path) }
        guard !old.isEmpty else { return }
        var next = ((0..<maximumFileCount).last { manager.fileExists(atPath: file($0).path) } ?? -1) + 1
        lock.withLock { _ in
            for url in old {
                if next < maximumFileCount, (try? manager.moveItem(at: url, to: file(next))) != nil {
                    next += 1
                } else {
                    try? manager.removeItem(at: url)
                }
            }
        }
    }

    /// Appends one entry. Errors while writing are ignored: logging must never break the app.
    public func log(_ category: Category, _ message: String) {
        let time = now().formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current))
        let text = message.replacingOccurrences(of: "\n", with: " ")
        let line = Data("\(time) [\(category.rawValue)] \(text)\n".utf8)
        unified.log("[\(category.rawValue, privacy: .public)] \(text, privacy: .public)")
        lock.withLock { _ in write(line) }
    }

    private func file(_ index: Int) -> URL {
        directory.appendingPathComponent(index == 0 ? "\(ProductName.name).log" : "\(ProductName.name).\(index).log")
    }

    private func write(_ line: Data) {
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let size = (try? manager.attributesOfItem(atPath: currentFile.path)[.size] as? Int) ?? 0
        if size > 0, size + line.count > maximumFileSize { rotate() }
        if !manager.fileExists(atPath: currentFile.path) {
            manager.createFile(atPath: currentFile.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: currentFile) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
    }

    private func rotate() {
        let manager = FileManager.default
        try? manager.removeItem(at: file(maximumFileCount - 1))
        guard maximumFileCount > 1 else { return }
        for index in stride(from: maximumFileCount - 2, through: 0, by: -1) where manager.fileExists(atPath: file(index).path) {
            try? manager.moveItem(at: file(index), to: file(index + 1))
        }
    }
}
