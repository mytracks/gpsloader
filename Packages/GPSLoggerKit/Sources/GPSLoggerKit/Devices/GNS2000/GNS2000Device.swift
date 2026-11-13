// GNS 2000 / GNS 2000 plus logger protocol (change gns2000-driver). Own code, written anew after the
// author's own myTracks driver (DsTrackFramework GpsDriver/GNS2000.m, 2013); no third-party source used.

import Foundation

/// Reads and erases the GNS 2000 Bluetooth logger (spec `gns2000-device`).
///
/// The device sends NMEA sentences all the time. After the first one, the driver sends `$PGNS,R` and receives
/// the memory as `$PMTKLOX` lines with 16-byte records, or sends `$PGNS,C` to erase it.
public struct GNS2000Device: DeviceProtocol {
    public init() {}

    /// Reference time of the week rollover correction; `nil` means the time of reading (tests set it).
    var referenceDate: Date?

    public var eraseSupport: DeviceErase { .supported }

    /// Names under which the device is paired, and the SDP service with its RFCOMM channel.
    public static let deviceNames = ["GNS 2000", "GNS 2000 plus"]
    public static let serviceName = "GNS GPS"

    static let timeout: TimeInterval = 10
    static let maxEraseRequests = 5
    static let lineLength = 4096

    public func read(_ connection: any DeviceConnection, _ reporter: DeviceReporter) async throws -> Recording {
        let link = GNS2000Link(connection: connection)
        reporter.step("Connecting")
        try await link.waitUntilReady()
        try await link.send("PGNS,R")
        reporter.step("Reading memory")

        var tracks = GNS2000Tracks(reference: referenceDate ?? Date())
        var packetCount: Int?
        var packetsRead = 0
        var deadline = Date().addingTimeInterval(Self.timeout)
        while true {
            let line = try await link.line(until: deadline)
            guard let sentence = GNS2000Sentence(line), sentence.identifier == "$PMTKLOX",
                  let type = sentence.arguments.first else { continue }
            switch (type, packetCount) {
            case ("0", nil) where sentence.arguments.count > 1:
                packetCount = Int(sentence.arguments[1]) ?? 0
                reporter.progress(0, of: packetCount ?? 0, step: "Reading memory")
            case ("1", let total?) where sentence.arguments.count > 1:
                for record in Self.records(sentence.arguments.dropFirst(2)) {
                    if let point = Self.point(record) { tracks.add(point) }
                }
                packetsRead += 1
                reporter.progress(min(packetsRead, total), of: total, step: "Reading memory")
            case ("2", .some):
                return Recording(tracks: tracks.result)
            default:
                continue
            }
            deadline = Date().addingTimeInterval(Self.timeout)
        }
    }

    public func erase(_ connection: any DeviceConnection, _ reporter: DeviceReporter) async throws {
        let link = GNS2000Link(connection: connection)
        reporter.step("Connecting")
        try await link.waitUntilReady()
        reporter.step("Erasing")
        try await link.send("PGNS,C")
        var requests = 1
        var linesWithoutP = 0
        while true {
            let line = try await link.line(until: Date().addingTimeInterval(Self.timeout))
            if GNS2000Sentence(line)?.identifier == "$PMTK001" { return }
            linesWithoutP = line.hasPrefix("$P") ? 0 : linesWithoutP + 1
            if linesWithoutP > 10 {
                guard requests < Self.maxEraseRequests else {
                    throw DeviceProtocolError("The GNS 2000 did not confirm erasing")
                }
                try await link.send("PGNS,C")
                requests += 1
                linesWithoutP = 0
            }
        }
    }

    /// Groups of four 8-digit hex words; each group is one 16-byte record in text order.
    static func records(_ words: ArraySlice<String>) -> [[UInt8]] {
        let words = Array(words)
        return stride(from: 0, to: words.count - 3, by: 4).compactMap { i in
            let text = words[i..<(i + 4)].joined()
            guard text.utf8.count == 32 else { return nil }
            var bytes: [UInt8] = []
            var index = text.startIndex
            while index < text.endIndex {
                let next = text.index(index, offsetBy: 2)
                guard let byte = UInt8(text[index..<next], radix: 16) else { return nil }
                bytes.append(byte)
                index = next
            }
            return bytes
        }
    }

    /// A record: time (UInt32), fix type (UInt8), latitude, longitude (Float32), height (Int16), little endian.
    /// All-`FF` records and fix types outside 1…4 carry no point. Byte 15 is not evaluated, as in myTracks.
    static func point(_ r: [UInt8]) -> TrackPoint? {
        guard r.count == 16, !r.allSatisfy({ $0 == 0xFF }), (1...4).contains(r[4]) else { return nil }
        func u32(_ o: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(r[o + $1]) << (8 * UInt32($1)) } }
        let height = Int16(bitPattern: UInt16(r[13]) | UInt16(r[14]) << 8)
        return TrackPoint(latitude: Double(Float(bitPattern: u32(5))), longitude: Double(Float(bitPattern: u32(9))),
                          elevation: Double(height), time: Date(timeIntervalSince1970: TimeInterval(u32(0))))
    }
}

/// A checked sentence: identifier (with `$`) and arguments, as `splitResponse` in myTracks.
struct GNS2000Sentence: Equatable {
    var identifier: String
    var arguments: [String]

    /// `nil` without `*`, with a wrong checksum or with fewer than two fields.
    init?(_ line: String) {
        guard line.first == "$", let star = line.lastIndex(of: "*") else { return nil }
        let body = line[line.index(after: line.startIndex)..<star]
        let sum = line[line.index(after: star)...]
        guard let expected = UInt8(sum, radix: 16), sum.count == 2,
              body.utf8.reduce(0, ^) == expected else { return nil }
        let fields = body.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 2 else { return nil }
        identifier = "$" + fields[0]
        arguments = Array(fields.dropFirst())
    }

    /// `calculateChecksum`/`sendCommand`: `$<body>*xx\r\n`, checksum in lower case.
    static func command(_ body: String) -> [UInt8] {
        Array("$\(body)*\(String(format: "%02x", body.utf8.reduce(0, ^)))\r\n".utf8)
    }
}

/// Line layer on top of the connection.
struct GNS2000Link {
    let connection: any DeviceConnection

    func send(_ body: String) async throws {
        try await connection.write(GNS2000Sentence.command(body))
    }

    /// The next CR LF line; fails when `deadline` passes without one.
    func line(until deadline: Date) async throws -> String {
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { throw DeviceProtocolError("No answer from the GNS 2000") }
        let bytes = try await connection.readUntil([0x0D, 0x0A], maxLength: GNS2000Device.lineLength, timeout: remaining)
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Waits for the first line starting with `$` (NMEA output shows the device is ready).
    func waitUntilReady() async throws {
        let deadline = Date().addingTimeInterval(GNS2000Device.timeout)
        while try await !line(until: deadline).hasPrefix("$") {}
    }
}

/// Splits the points into tracks where the time goes backwards; tracks are named after their first point (UTC).
/// Times are corrected for GPS week rollovers first, so that names and splits follow the corrected times
/// (spec `device-mode`, "Korrektur des GPS-Wochenüberlaufs beim Auslesen").
struct GNS2000Tracks {
    let reference: Date
    private var tracks: [[TrackPoint]] = [[]]
    private var previous: Date?

    init(reference: Date) {
        self.reference = reference
    }

    mutating func add(_ point: TrackPoint) {
        var point = point
        point.time = point.time.map { RecordingProcessing.corrected($0, reference: reference) }
        if let previous, let time = point.time, time < previous, !(tracks.last?.isEmpty ?? true) {
            tracks.append([])
        }
        tracks[tracks.count - 1].append(point)
        previous = point.time
    }

    var result: [Track] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return tracks.filter { !$0.isEmpty }.map { points in
            Track(name: points[0].time.map(formatter.string(from:)), segments: [TrackSegment(points: points)])
        }
    }
}
