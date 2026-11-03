import Foundation
import GPSLoggerKit
import LoggerCore

/// Writes GPX files for the app; the format itself comes from GPSLoggerKit's `GPXWriter`.
public enum GPXExport {
    /// Writes `recording` atomically as GPX 1.1.
    /// - Throws: `LoggerError` of kind `.writeFailed`, so the app shows its usual message.
    public static func write(_ recording: Recording, to url: URL, creator: String, createdAt: Date = Date()) throws {
        do {
            try GPXWriter(creator: creator).write(recording, to: url, createdAt: createdAt)
        } catch let error as GPSLoggerError {
            throw LoggerError(.writeFailed, detail: error.detail.isEmpty ? error.fileName : error.detail)
        }
    }
}
