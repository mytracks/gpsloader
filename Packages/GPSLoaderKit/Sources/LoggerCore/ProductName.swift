import Foundation

/// The name users see and the names of the app's folders and files (change rename-and-icon, design D2).
/// Constants rather than bundle values, so the packages stay testable without the app bundle.
public enum ProductName {
    /// "myTracks Loader"
    public static let name = "myTracks Loader"
    /// Stem of file names that may end up on GitHub or in mail: no spaces ("myTracks-Loader").
    public static let fileStem = "myTracks-Loader"
    /// The former name; folders and crash reports of earlier builds still carry it.
    public static let legacyName = "gpsloader"
}

/// Moves a folder of an earlier build to its new name (spec `support-package`, "App-Protokoll").
public enum LegacyFolderMigration {
    public enum Outcome: Equatable, Sendable {
        /// There was no old folder.
        case nothingToMove
        /// The new folder exists already; the old one stays untouched.
        case keptBoth
        case moved
        /// Moving failed; the old folder stays, the app writes to the new one.
        case failed(String)
    }

    /// Moves `old` to `new` if `old` exists and `new` does not. Synchronous; call before the folder is first used.
    @discardableResult
    public static func migrate(from old: URL, to new: URL, fileManager: FileManager = .default) -> Outcome {
        guard fileManager.fileExists(atPath: old.path) else { return .nothingToMove }
        guard !fileManager.fileExists(atPath: new.path) else { return .keptBoth }
        do {
            try fileManager.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: old, to: new)
            return .moved
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
