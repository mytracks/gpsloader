import Foundation

/// A single recorded position.
public struct TrackPoint: Sendable, Hashable {
    /// Latitude in degrees (WGS 84).
    public var latitude: Double
    /// Longitude in degrees (WGS 84).
    public var longitude: Double
    /// Elevation in meters, if the device recorded one.
    public var elevation: Double?
    /// Time of the fix (absolute point in time; exported as UTC).
    public var time: Date?

    public init(latitude: Double, longitude: Double, elevation: Double? = nil, time: Date? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.time = time
    }
}

/// A continuous sequence of track points.
public struct TrackSegment: Sendable, Hashable {
    public var points: [TrackPoint]

    public init(points: [TrackPoint] = []) {
        self.points = points
    }
}

/// A track as delivered by a logger, made of one or more segments.
public struct Track: Sendable, Hashable {
    public var name: String?
    public var segments: [TrackSegment]

    public init(name: String? = nil, segments: [TrackSegment] = []) {
        self.name = name
        self.segments = segments
    }

    /// Number of points over all segments.
    public var pointCount: Int {
        segments.reduce(0) { $0 + $1.points.count }
    }
}

/// A single marked position (e.g. a waypoint button press on the logger).
public struct Waypoint: Sendable, Hashable {
    public var latitude: Double
    public var longitude: Double
    public var elevation: Double?
    public var time: Date?
    public var name: String?
    public var comment: String?

    public init(latitude: Double, longitude: Double, elevation: Double? = nil, time: Date? = nil,
                name: String? = nil, comment: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.time = time
        self.name = name
        self.comment = comment
    }
}

/// Everything read from a logger in one operation.
public struct Recording: Sendable, Hashable {
    public var tracks: [Track]
    public var waypoints: [Waypoint]

    public init(tracks: [Track] = [], waypoints: [Waypoint] = []) {
        self.tracks = tracks
        self.waypoints = waypoints
    }

    /// Number of track points over all tracks.
    public var trackPointCount: Int {
        tracks.reduce(0) { $0 + $1.pointCount }
    }

    /// A recording is empty when it contains neither track points nor waypoints.
    public var isEmpty: Bool {
        trackPointCount == 0 && waypoints.isEmpty
    }
}
