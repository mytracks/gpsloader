import Foundation

/// Post-processing applied after a format was read.
public enum RecordingProcessing {
    /// 1024 GPS weeks in seconds.
    static let rolloverInterval: TimeInterval = 1024 * 7 * 86_400
    /// Threshold: times more than 512 weeks before the reference are considered rolled over.
    static let rolloverThreshold: TimeInterval = 512 * 7 * 86_400

    /// Corrects GPS week number rollovers: as long as a time lies more than 512 weeks before
    /// `reference`, 1024 weeks are added. Applies to track points and waypoints.
    public static func correctingWeekRollover(_ recording: Recording, reference: Date) -> Recording {
        var result = recording
        for t in result.tracks.indices {
            for s in result.tracks[t].segments.indices {
                for p in result.tracks[t].segments[s].points.indices {
                    if let time = result.tracks[t].segments[s].points[p].time {
                        result.tracks[t].segments[s].points[p].time = corrected(time, reference: reference)
                    }
                }
            }
        }
        for w in result.waypoints.indices {
            if let time = result.waypoints[w].time {
                result.waypoints[w].time = corrected(time, reference: reference)
            }
        }
        return result
    }

    static func corrected(_ time: Date, reference: Date) -> Date {
        var time = time
        while reference.timeIntervalSince(time) > rolloverThreshold {
            time = time.addingTimeInterval(rolloverInterval)
        }
        return time
    }

    /// When the recording has no track points but waypoints, adds one track made of the waypoints
    /// in their order. The waypoints are kept. Otherwise the recording is returned unchanged.
    public static func waypointsAsTrack(_ recording: Recording) -> Recording {
        guard recording.trackPointCount == 0, !recording.waypoints.isEmpty else { return recording }
        var result = recording
        let points = recording.waypoints.map {
            TrackPoint(latitude: $0.latitude, longitude: $0.longitude, elevation: $0.elevation,
                       time: $0.time, quality: $0.quality)
        }
        result.tracks = [Track(segments: [TrackSegment(points: points)])]
        return result
    }
}
