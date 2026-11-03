import Foundation
import GPSLoggerKit

/// The files of one conversion, grouped by detected format (spec `file-conversion`).
public struct ConversionPlan: Sendable {
    /// Files of one format, in the order they were chosen.
    public struct Group: Sendable {
        public let formatID: FileFormatID
        public let inputs: [FileInput]
    }

    /// Groups in the order of their first file.
    public let groups: [Group]
    /// Names of the files whose format was not recognized, in the order they were chosen.
    public let unrecognized: [String]

    public init(groups: [Group], unrecognized: [String]) {
        self.groups = groups
        self.unrecognized = unrecognized
    }

    /// `true` if no file was recognized.
    public var isEmpty: Bool { groups.isEmpty }

    /// The same plan without the unrecognized files.
    public func excludingUnrecognized() -> ConversionPlan {
        ConversionPlan(groups: groups, unrecognized: [])
    }

    /// Name of the first recognized file.
    var firstFileName: String? { groups.first?.inputs.first?.name }
}

/// Converts files of the formats supported by GPSLoggerKit into one recording (spec `file-conversion`).
public enum FileConverter {
    /// Loads the files (memory mapped) and detects their formats.
    /// - Throws: `GPSLoggerError(.unreadable)` for a file that cannot be read, `.empty` for an empty file.
    public static func plan(for urls: [URL]) throws -> ConversionPlan {
        var order: [FileFormatID] = []
        var inputsByFormat: [FileFormatID: [FileInput]] = [:]
        var unrecognized: [String] = []
        for url in urls {
            let input = try FileInput.load(url)
            guard !input.data.isEmpty else { throw GPSLoggerError(.empty, fileName: input.name) }
            guard let format = FileFormats.detect(prefix: input.data.prefix(FileFormats.sniffLength),
                                                  fileName: input.name) else {
                unrecognized.append(input.name)
                continue
            }
            if inputsByFormat[format.id] == nil { order.append(format.id) }
            inputsByFormat[format.id, default: []].append(input)
        }
        return ConversionPlan(groups: order.map { ConversionPlan.Group(formatID: $0, inputs: inputsByFormat[$0]!) },
                              unrecognized: unrecognized)
    }

    /// Reads all groups of the plan, merges their results (tracks first, then waypoints, both in group order)
    /// and post-processes them: week rollover correction per group, waypoints as track on the merged result.
    /// - Throws: `GPSLoggerError` of the formats, `.noUsableData` if the plan is empty, or `CancellationError`.
    public static func convert(_ plan: ConversionPlan, referenceDate: Date = Date()) async throws -> ImportResult {
        guard let firstName = plan.firstFileName else {
            throw GPSLoggerError(.noUsableData, fileName: plan.unrecognized.first ?? "")
        }
        let options = ImportOptions(correctWeekRollover: true, referenceDate: referenceDate,
                                    waypointsAsTrackWhenNoTracks: false)
        var recording = Recording()
        var warnings: [ImportWarning] = []
        for group in plan.groups {
            try Task.checkCancellation()
            guard let format = FileFormats.format(withID: group.formatID) else { continue }
            let result = try await FileFormats.read(group.inputs, format: format, options: options)
            recording.tracks += result.recording.tracks
            recording.waypoints += result.recording.waypoints
            warnings += result.warnings
        }
        recording = RecordingProcessing.waypointsAsTrack(recording)
        guard !recording.isEmpty else { throw GPSLoggerError(.noUsableData, fileName: firstName) }
        return ImportResult(recording: recording, warnings: warnings)
    }

    /// "<first file name without extension>.gpx", e.g. "flug1.gpx" for "flug1.igc".
    public static func suggestedFileName(for urls: [URL]) -> String {
        let base = urls.first.map { $0.deletingPathExtension().lastPathComponent } ?? ""
        return (base.isEmpty ? "GPS" : base) + ".gpx"
    }
}
