import Foundation

/// Kind of position fix reported by a receiver.
public enum FixType: String, Sendable, Hashable, CaseIterable {
    case none
    case twoD = "2d"
    case threeD = "3d"
    case dgps
}

/// Optional quality and motion values of a position. All values use SI units.
public struct PositionQuality: Sendable, Hashable {
    /// Speed over ground in meters per second.
    public var speed: Double?
    /// Course over ground in degrees (0...360, true north).
    public var course: Double?
    /// Number of satellites used for the fix.
    public var satellites: Int?
    public var hdop: Double?
    public var vdop: Double?
    public var pdop: Double?
    public var fix: FixType?

    public init(speed: Double? = nil, course: Double? = nil, satellites: Int? = nil,
                hdop: Double? = nil, vdop: Double? = nil, pdop: Double? = nil, fix: FixType? = nil) {
        self.speed = speed
        self.course = course
        self.satellites = satellites
        self.hdop = hdop
        self.vdop = vdop
        self.pdop = pdop
        self.fix = fix
    }

    /// True when no value is set.
    public var isEmpty: Bool {
        self == PositionQuality()
    }
}

/// A single recorded position.
public struct TrackPoint: Sendable, Hashable {
    /// Latitude in degrees (WGS 84).
    public var latitude: Double
    /// Longitude in degrees (WGS 84).
    public var longitude: Double
    /// Elevation in meters, if recorded.
    public var elevation: Double?
    /// Time of the fix (absolute point in time; exported as UTC).
    public var time: Date?
    /// Quality and motion values, if recorded.
    public var quality: PositionQuality

    public init(latitude: Double, longitude: Double, elevation: Double? = nil, time: Date? = nil,
                quality: PositionQuality = PositionQuality()) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.time = time
        self.quality = quality
    }
}

/// A continuous sequence of track points.
public struct TrackSegment: Sendable, Hashable {
    public var points: [TrackPoint]

    public init(points: [TrackPoint] = []) {
        self.points = points
    }
}

/// A track made of one or more segments.
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

/// A single marked position.
public struct Waypoint: Sendable, Hashable {
    public var latitude: Double
    public var longitude: Double
    public var elevation: Double?
    public var time: Date?
    public var name: String?
    public var comment: String?
    public var quality: PositionQuality

    public init(latitude: Double, longitude: Double, elevation: Double? = nil, time: Date? = nil,
                name: String? = nil, comment: String? = nil, quality: PositionQuality = PositionQuality()) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.time = time
        self.name = name
        self.comment = comment
        self.quality = quality
    }
}

/// Everything read in one operation.
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
