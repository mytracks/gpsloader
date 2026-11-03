import Foundation

/// Stable identifier of a file format, e.g. `nmea` or `gpx`.
public struct FileFormatID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var description: String { rawValue }

    public static let nmea: FileFormatID = "nmea"
    public static let gpx: FileFormatID = "gpx"
    public static let igc: FileFormatID = "igc"
}

/// The content of one input file.
public struct FileInput: Sendable {
    /// File name used in errors and warnings.
    public var name: String
    public var data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }

    /// Reads a file (memory mapped where possible).
    /// Security-scoped access on iOS is the caller's responsibility.
    /// - Throws: `GPSLoggerError` of kind `.unreadable`.
    public static func load(_ url: URL) throws -> FileInput {
        do {
            return FileInput(name: url.lastPathComponent, data: try Data(contentsOf: url, options: .mappedIfSafe))
        } catch {
            throw GPSLoggerError(.unreadable, fileName: url.lastPathComponent, detail: error.localizedDescription)
        }
    }
}

/// A readable file format.
///
/// Implementations are stateless value types. `read` is synchronous, checks for task cancellation
/// regularly (throwing `CancellationError`) and must not be called on the main actor for large files.
public protocol FileFormat: Sendable {
    var id: FileFormatID { get }
    /// Localized, human readable name.
    var displayName: String { get }
    /// Typical file extensions, lower case, without dot.
    var fileExtensions: [String] { get }
    /// Whether the start of a file (up to ``FileFormats/sniffLength`` bytes) looks like this format.
    func matches(prefix: Data) -> Bool
    /// Reads one or more files into one recording, without post-processing.
    func read(_ inputs: [FileInput]) throws -> ImportResult
}

/// Options for ``FileFormats/read(_:format:options:)``.
public struct ImportOptions: Sendable {
    /// Correct GPS week number rollovers (see ``RecordingProcessing/correctingWeekRollover(_:reference:)``).
    public var correctWeekRollover: Bool
    /// Reference time for the rollover correction; defaults to now.
    public var referenceDate: Date
    /// Turn waypoints into a track when the result contains no track points.
    public var waypointsAsTrackWhenNoTracks: Bool

    public init(correctWeekRollover: Bool = true, referenceDate: Date = Date(),
                waypointsAsTrackWhenNoTracks: Bool = false) {
        self.correctWeekRollover = correctWeekRollover
        self.referenceDate = referenceDate
        self.waypointsAsTrackWhenNoTracks = waypointsAsTrackWhenNoTracks
    }
}

/// The result of reading files: the recording and summarized warnings.
public struct ImportResult: Sendable {
    public var recording: Recording
    public var warnings: [ImportWarning]

    public init(recording: Recording, warnings: [ImportWarning] = []) {
        self.recording = recording
        self.warnings = warnings
    }
}

/// The catalog of supported formats and the common entry points.
public enum FileFormats {
    /// Number of bytes from the start of a file used for detection.
    public static let sniffLength = 4096

    /// All supported formats.
    public static let all: [any FileFormat] = [NMEAFileFormat(), GPXFileFormat(), IGCFileFormat()]

    /// The format with the given identifier.
    public static func format(withID id: FileFormatID) -> (any FileFormat)? {
        all.first { $0.id == id }
    }

    /// Suggests a format by content. The file extension only decides which formats are checked first.
    /// - Returns: `nil` if no format recognizes the content ("unknown").
    public static func detect(prefix: Data, fileName: String? = nil) -> (any FileFormat)? {
        let head = prefix.prefix(sniffLength)
        let fileExtension = fileName.map { ($0 as NSString).pathExtension.lowercased() } ?? ""
        let ordered = all.filter { $0.fileExtensions.contains(fileExtension) }
            + all.filter { !$0.fileExtensions.contains(fileExtension) }
        return ordered.first { $0.matches(prefix: head) }
    }

    /// Reads the files with the given format and applies the post-processing chosen in `options`.
    ///
    /// - Throws: `GPSLoggerError` (`.empty` for an empty file, `.noUsableData` when nothing usable was found,
    ///   or the format's own errors) or `CancellationError`.
    public static func readSynchronously(_ inputs: [FileInput], format: any FileFormat,
                                         options: ImportOptions = ImportOptions()) throws -> ImportResult {
        if let empty = inputs.first(where: { $0.data.isEmpty }) {
            throw GPSLoggerError(.empty, fileName: empty.name)
        }
        var result = try format.read(inputs)
        try Task.checkCancellation()
        if result.recording.isEmpty {
            throw GPSLoggerError(.noUsableData, fileName: inputs.map(\.name).joined(separator: ", "))
        }
        if options.correctWeekRollover {
            result.recording = RecordingProcessing.correctingWeekRollover(result.recording, reference: options.referenceDate)
        }
        if options.waypointsAsTrackWhenNoTracks {
            result.recording = RecordingProcessing.waypointsAsTrack(result.recording)
        }
        return result
    }

    /// Asynchronous variant of ``readSynchronously(_:format:options:)``. It runs off the caller's actor
    /// (nonisolated async) and ends with `CancellationError` when the calling task is cancelled.
    public static func read(_ inputs: [FileInput], format: any FileFormat,
                            options: ImportOptions = ImportOptions()) async throws -> ImportResult {
        try readSynchronously(inputs, format: format, options: options)
    }
}

/// Cooperative cancellation for parsers: checks the task every `interval` units of work.
struct CancellationCheck {
    let interval: Int
    private var counter = 0

    init(interval: Int = 4096) {
        self.interval = interval
    }

    mutating func tick() throws {
        counter += 1
        if counter >= interval {
            counter = 0
            try Task.checkCancellation()
        }
    }
}
