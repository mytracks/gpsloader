import Foundation
import Testing
@testable import GPSLoggerKit

struct SimulatedTimeout: Error, Equatable {}

/// A simulated logger behind a `DeviceConnection`: `respond` gets every write and returns the bytes the device
/// sends back. Reads that cannot be satisfied fail immediately with `SimulatedTimeout`.
actor SimulatedDevice: DeviceConnection {
    typealias Responder = @Sendable (_ written: [UInt8]) -> [UInt8]

    private var input: [UInt8]
    private let respond: Responder
    private(set) var written: [[UInt8]] = []

    init(initialInput: [UInt8] = [], respond: @escaping Responder) {
        input = initialInput
        self.respond = respond
    }

    func write(_ bytes: [UInt8]) async throws {
        try Task.checkCancellation()
        written.append(bytes)
        input += respond(bytes)
    }

    func read(count: Int, timeout: TimeInterval) async throws -> [UInt8] {
        guard input.count >= count else { throw SimulatedTimeout() }
        defer { input.removeFirst(count) }
        return Array(input.prefix(count))
    }

    func readUntil(_ terminator: [UInt8], maxLength: Int, timeout: TimeInterval) async throws -> [UInt8] {
        guard input.count >= terminator.count else { throw SimulatedTimeout() }
        for end in terminator.count...input.count where Array(input[(end - terminator.count)..<end]) == terminator {
            let bytes = Array(input.prefix(end - terminator.count))
            input.removeFirst(end)
            return bytes
        }
        throw SimulatedTimeout()
    }

    func discardInput() async { input.removeAll() }
    func setBaudRate(_ rate: Int) async throws {}
    var pendingInput: [UInt8] { input }
}

/// Builds GNS 2000 sentences and records (no real location data).
enum GNS2000TestData {
    static func sentence(_ body: String, checksum: UInt8? = nil) -> String {
        "$\(body)*\(String(format: "%02X", checksum ?? body.utf8.reduce(0, ^)))\r\n"
    }

    static let nmea = sentence("GPGGA,120000,5030.000,N,00815.000,E,1,05,1.0,100.0,M,,,,")

    static func record(time: UInt32, fix: UInt8 = 3, latitude: Float, longitude: Float, height: Int16) -> [UInt8] {
        func le<T: FixedWidthInteger>(_ v: T) -> [UInt8] { withUnsafeBytes(of: v.littleEndian, Array.init) }
        return le(time) + [fix] + le(latitude.bitPattern) + le(longitude.bitPattern) + le(height) + [0]
    }

    static let empty = [UInt8](repeating: 0xFF, count: 16)

    /// `$PMTKLOX,1,<index>,<words…>`: four 8-digit hex words per record.
    static func packet(_ index: Int, _ records: [[UInt8]], checksum: UInt8? = nil) -> String {
        let words = records.flatMap { record in
            stride(from: 0, to: 16, by: 4).map { record[$0..<($0 + 4)].map { String(format: "%02X", $0) }.joined() }
        }
        return sentence((["PMTKLOX", "1", String(index)] + words).joined(separator: ","), checksum: checksum)
    }

    static let start: UInt32 = 1_793_620_800  // 2026-11-02T12:00:00Z

    /// 40 records in three packets: 36 valid points, 2 empty slots, 2 with an invalid fix.
    static func memory() -> [[[UInt8]]] {
        var records = (0..<40).map { k in
            record(time: start + UInt32(k), latitude: 50 + Float(k) * 0.001, longitude: 8 + Float(k) * 0.001, height: 100)
        }
        records[5] = empty
        records[39] = empty
        records[20] = record(time: start + 20, fix: 0, latitude: 1, longitude: 1, height: 0)
        records[21] = record(time: start + 21, fix: 5, latitude: 1, longitude: 1, height: 0)
        return [Array(records[0..<14]), Array(records[14..<28]), Array(records[28..<40])]
    }
}

/// A simulated GNS 2000 (spec `gns2000-device`).
final class GNS2000Simulator: @unchecked Sendable {
    private let lock = NSLock()
    var packets: [[[UInt8]]] = GNS2000TestData.memory()
    var corruptPacket: Int?
    var sendsEnd = true
    var ignoredEraseRequests = 0
    private(set) var eraseRequests = 0

    func respond(_ written: [UInt8]) -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }
        switch written {
        case GNS2000Sentence.command("PGNS,R"):
            var text = GNS2000TestData.nmea + GNS2000TestData.sentence("PMTKLOX,0,\(packets.count)")
            for (index, records) in packets.enumerated() {
                text += GNS2000TestData.packet(index, records, checksum: index == corruptPacket ? 0 : nil)
            }
            if sendsEnd { text += GNS2000TestData.sentence("PMTKLOX,2") }
            return Array(text.utf8)
        case GNS2000Sentence.command("PGNS,C"):
            eraseRequests += 1
            if eraseRequests <= ignoredEraseRequests {
                return Array(String(repeating: GNS2000TestData.nmea, count: 15).utf8)
            }
            return Array(GNS2000TestData.sentence("PMTK001,182,3").utf8)
        default:
            return []
        }
    }
}

/// Thread-safe collector for reports.
final class ReportLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [Int] = []
    var values: [Int] { lock.lock(); defer { lock.unlock() }; return entries }
    func add(_ value: Int) { lock.lock(); entries.append(value); lock.unlock() }
}

private func device(_ simulator: GNS2000Simulator, ready: Bool = true) -> SimulatedDevice {
    SimulatedDevice(initialInput: ready ? Array(("GA,partial\r\n" + GNS2000TestData.nmea).utf8) : []) { simulator.respond($0) }
}

@Suite("GNS 2000 device")
struct GNS2000DeviceTests {
    /// Scenario "Prüfsumme eines Befehls".
    @Test func commandChecksum() {
        #expect(GNS2000Sentence.command("PGNS,R") == Array("$PGNS,R*74\r\n".utf8))
        #expect(GNS2000Sentence.command("PGNS,C") == Array("$PGNS,C*65\r\n".utf8))
    }

    /// Scenarios "Gerät sendet NMEA" and "Auslesen"; also "Treiber mit simuliertem Gerät" (spec `logger-kit`).
    @Test func readsTheMemory() async throws {
        let simulator = GNS2000Simulator()
        let connection = device(simulator)
        let progress = ReportLog()
        let recording = try await GNS2000Device().read(connection, DeviceReporter(progress: { done, _, _ in progress.add(done) }))
        #expect(recording.tracks.count == 1)
        #expect(recording.trackPointCount == 36)
        #expect(recording.tracks.first?.name == "2026-11-02 12:00")
        #expect(progress.values == [0, 1, 2, 3])
        #expect(await connection.written == [GNS2000Sentence.command("PGNS,R")])
    }

    /// Scenario "Umrechnung".
    @Test func conversion() throws {
        let record = GNS2000TestData.record(time: 1_793_620_800, latitude: 50.5, longitude: 8.25, height: 123)
        #expect(record.map { String(format: "%02X", $0) }.joined() == "407BE86A0300004A42000004417B0000")
        let point = try #require(GNS2000Device.point(record))
        #expect(point.latitude == 50.5 && point.longitude == 8.25 && point.elevation == 123)
        #expect(point.time == ISO8601DateFormatter().date(from: "2026-11-02T12:00:00Z"))
        let negative = GNS2000TestData.record(time: 1, latitude: -33.5, longitude: -70.25, height: -12)
        #expect(GNS2000Device.point(negative).map { [$0.latitude, $0.longitude, $0.elevation ?? 0] } == [-33.5, -70.25, -12])
    }

    /// Scenario "Ungültiger Fix" and empty slots.
    @Test func invalidRecords() {
        #expect(GNS2000Device.point(GNS2000TestData.record(time: 1, fix: 0, latitude: 1, longitude: 1, height: 0)) == nil)
        #expect(GNS2000Device.point(GNS2000TestData.record(time: 1, fix: 5, latitude: 1, longitude: 1, height: 0)) == nil)
        #expect(GNS2000Device.point(GNS2000TestData.empty) == nil)
        #expect(GNS2000Device.records(["0011", "22", "33", "44"]).isEmpty)  // too short
        #expect(GNS2000Device.records(["ZZ000000", "00000000", "00000000", "00000000"]).isEmpty)  // not hex
    }

    /// Scenario "Gestörte Zeile": the packet with a wrong checksum is skipped.
    @Test func corruptLineIsSkipped() async throws {
        let simulator = GNS2000Simulator()
        simulator.corruptPacket = 1
        let recording = try await GNS2000Device().read(device(simulator), DeviceReporter())
        #expect(recording.trackPointCount == 36 - 12)  // packet 1 holds 14 records, 2 of them invalid
        #expect(GNS2000Sentence("$PMTKLOX,2*00") == nil)
        #expect(GNS2000Sentence("$PMTKLOX,2") == nil)
        #expect(GNS2000Sentence("$PMTKLOX,2*47")?.arguments == ["2"])
        #expect(GNS2000Sentence("$GPGGA,120000,5030.000,N,00815.000,E,1,05,1.0,100.0,M,,,,*1d")?.identifier == "$GPGGA")  // lower case
    }

    /// Scenario "Gerät stumm".
    @Test func silentDevice() async {
        await #expect(throws: SimulatedTimeout.self) {
            try await GNS2000Device().read(device(GNS2000Simulator(), ready: false), DeviceReporter())
        }
    }

    /// Scenario "Ende fehlt".
    @Test func missingEnd() async {
        let simulator = GNS2000Simulator()
        simulator.sendsEnd = false
        await #expect(throws: SimulatedTimeout.self) {
            try await GNS2000Device().read(device(simulator), DeviceReporter())
        }
    }

    /// Scenario "Zeit springt zurück".
    @Test func timeGoesBackwards() async throws {
        let simulator = GNS2000Simulator()
        let earlier = GNS2000TestData.start - 28 * 3600  // 2026-11-01T08:00:00Z
        simulator.packets = [
            (0..<3).map { GNS2000TestData.record(time: GNS2000TestData.start + UInt32($0), latitude: 50, longitude: 8, height: 0) },
            (0..<2).map { GNS2000TestData.record(time: earlier + UInt32($0), latitude: 51, longitude: 9, height: 0) },
        ]
        let recording = try await GNS2000Device().read(device(simulator), DeviceReporter())
        #expect(recording.tracks.map(\.name) == ["2026-11-02 12:00", "2026-11-01 08:00"])
        #expect(recording.tracks.map(\.pointCount) == [3, 2])
    }

    /// Scenario "Tracknamen nach der Korrektur" (spec `device-mode`): names follow the corrected times, and the
    /// jump back at the rollover in the middle of the memory does not start a new track.
    @Test func weekRolloverIsCorrectedBeforeSplitting() async throws {
        let weeks1024: UInt32 = 1024 * 7 * 86_400
        var driver = GNS2000Device()
        driver.referenceDate = ISO8601DateFormatter().date(from: "2026-11-13T10:00:00Z")

        // Two recordings, all times 1024 weeks too early.
        let earlier = GNS2000TestData.start - 28 * 3600  // 2026-11-01T08:00:00Z
        let rolledOver = GNS2000Simulator()
        rolledOver.packets = [
            (0..<3).map { GNS2000TestData.record(time: GNS2000TestData.start + UInt32($0) - weeks1024, latitude: 50, longitude: 8, height: 0) },
            (0..<2).map { GNS2000TestData.record(time: earlier + UInt32($0) - weeks1024, latitude: 51, longitude: 9, height: 0) },
        ]
        let recording = try await driver.read(device(rolledOver), DeviceReporter())
        #expect(recording.tracks.map(\.name) == ["2026-11-02 12:00", "2026-11-01 08:00"])
        #expect(recording.tracks.map(\.pointCount) == [3, 2])
        #expect(recording.tracks[0].segments[0].points.first?.time == Date(timeIntervalSince1970: TimeInterval(GNS2000TestData.start)))

        // The rollover happens in the middle of one recording.
        let beforeRollover = UInt32(1_554_465_600)  // 2019-04-05T12:00:00Z, still correct
        let midway = GNS2000Simulator()
        midway.packets = [
            (0..<2).map { GNS2000TestData.record(time: beforeRollover + UInt32($0), latitude: 50, longitude: 8, height: 0) },
            (2..<4).map { GNS2000TestData.record(time: beforeRollover + UInt32($0) - weeks1024, latitude: 50, longitude: 8, height: 0) },
        ]
        let continuous = try await driver.read(device(midway), DeviceReporter())
        #expect(continuous.tracks.map(\.name) == ["2019-04-05 12:00"])
        let times = continuous.tracks.first?.segments.first?.points.compactMap(\.time).map(\.timeIntervalSince1970)
        #expect(times == (0..<4).map { TimeInterval(beforeRollover) + TimeInterval($0) })
    }

    /// Scenario "Löschen bestätigt".
    @Test func eraseConfirmed() async throws {
        let simulator = GNS2000Simulator()
        try await GNS2000Device().erase(device(simulator), DeviceReporter())
        #expect(simulator.eraseRequests == 1)
        #expect(GNS2000Device().eraseSupport == .supported)
    }

    /// Scenario "Gerät überhört den Befehl": resent after 11 lines without `$P`, at most five times.
    @Test func eraseIsRepeated() async throws {
        let simulator = GNS2000Simulator()
        simulator.ignoredEraseRequests = 1
        let connection = device(simulator)
        try await GNS2000Device().erase(connection, DeviceReporter())
        #expect(simulator.eraseRequests == 2)
        #expect(await connection.pendingInput.isEmpty)

        let stubborn = GNS2000Simulator()
        stubborn.ignoredEraseRequests = 99
        await #expect(throws: DeviceProtocolError("The GNS 2000 did not confirm erasing")) {
            try await GNS2000Device().erase(device(stubborn), DeviceReporter())
        }
        #expect(stubborn.eraseRequests == GNS2000Device.maxEraseRequests)
    }
}
