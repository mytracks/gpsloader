import Foundation
import Testing
import LoggerCore
import TestSupport
@testable import DiagnosticCapture

private let environment = CaptureEnvironment(appVersion: "0.1.0", osVersion: "Version 27.0", architecture: "arm64",
                                             isTranslated: false)

/// A tiny line based test driver: asks for the number of points, then reads each point.
private struct LineTestDriver {
    var transport: any ByteTransport
    /// Index sent for the second point; deviating from 1 provokes a replay mismatch.
    var secondIndex = 1

    func read() async throws -> Recording {
        try await transport.open()
        defer { Task { await transport.close() } }
        let crlf = Array("\r\n".utf8)
        try await transport.write(Array("$CNT\r\n".utf8))
        let countLine = String(decoding: try await transport.readUntil(crlf, maxLength: 64, timeout: 1), as: UTF8.self)
        let count = Int(countLine.split(separator: ",")[1]) ?? 0
        var points: [TrackPoint] = []
        for index in 0..<count {
            let requested = index == 1 ? secondIndex : index
            try await transport.write(Array("$PT,\(requested)\r\n".utf8))
            let fields = String(decoding: try await transport.readUntil(crlf, maxLength: 64, timeout: 1), as: UTF8.self)
                .split(separator: ",")
            points.append(TrackPoint(latitude: Double(fields[2])!, longitude: Double(fields[3])!))
        }
        return Recording(tracks: [Track(name: "fixture", segments: [TrackSegment(points: points)])])
    }
}

private let expectedRecording = Recording(tracks: [
    Track(name: "fixture", segments: [TrackSegment(points: [
        TrackPoint(latitude: 51.5, longitude: 8.5),
        TrackPoint(latitude: 51.6, longitude: 8.6),
    ])]),
])

private func fixtureData() throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "line-dialog", withExtension: "jsonl", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Suite("Diagnostic capture")
struct DiagnosticCaptureTests {
    // MARK: Recorder and format (task 5.1)

    /// Scenario "Serieller Dialog".
    @Test func recordsBytesInOrderWithTimestamps() throws {
        let recorder = CaptureRecorder(environment: environment)
        recorder.record(.header(DiagnosticHeader(driver: "test", port: "/dev/cu.x", parameters: ["baud": "9600"])))
        recorder.record(.transmitted(source: "/dev/cu.x", bytes: Array(0..<16)))
        recorder.record(.received(source: "/dev/cu.x", bytes: [0x93, 0x00, 0x00]))

        let (header, entries) = try CaptureFormat.decode(recorder.encoded())
        #expect(header.driver == "test")
        #expect(header.port == "/dev/cu.x")
        #expect(header.params == ["baud": "9600"])
        #expect(header.app == "0.1.0")
        #expect(header.arch == "arm64")
        #expect(header.translated == false)
        #expect(entries.count == 2)
        #expect(entries[0].kind == "tx")
        #expect(entries[0].bytes == Array(0..<16))
        #expect(entries[1].kind == "rx")
        #expect(entries[1].bytes == [0x93, 0x00, 0x00])
        #expect(entries[0].t != nil && entries[1].t != nil)
        #expect(entries[0].t! <= entries[1].t!)
    }

    @Test func everyLineIsValidJSON() throws {
        let recorder = CaptureRecorder(environment: environment)
        recorder.record(.received(source: "s", bytes: Array("$GPGGA,1\r\n".utf8)))
        recorder.record(.event(source: "s", name: "timeout", detail: "no \"data\""))
        let lines = recorder.encoded().split(separator: 0x0A)
        #expect(lines.count == 3)
        for line in lines {
            #expect(throws: Never.self) { try JSONSerialization.jsonObject(with: Data(line)) }
        }
    }

    /// Scenario "Datei im Texteditor": NMEA-like lines are readable as text.
    @Test func asciiColumnIsReadable() throws {
        let recorder = CaptureRecorder(environment: environment)
        recorder.record(.received(source: "s", bytes: Array("$PMTKLOX,0,12*6E\r\n".utf8)))
        let text = String(decoding: recorder.encoded(), as: UTF8.self)
        #expect(text.contains("$PMTKLOX,0,12*6E\\\\r\\\\n"))
    }

    /// Scenario "gpsbabel-Aufruf".
    @Test func recordsProcessInvocations() throws {
        let recorder = CaptureRecorder(environment: environment)
        recorder.record(.process(ProcessRecord(executable: "/x/gpsbabel", arguments: ["-i", "mtk", "-f", "/dev/cu.a b"],
                                               standardOutput: "out", standardError: "err", exitCode: 1,
                                               duration: 1.23456)))
        let entry = try #require(try CaptureFormat.decode(recorder.encoded()).entries.first)
        #expect(entry.kind == "process")
        #expect(entry.arguments == ["-i", "mtk", "-f", "/dev/cu.a b"])
        #expect(entry.stdout == "out")
        #expect(entry.stderr == "err")
        #expect(entry.exit == 1)
        #expect(entry.duration == 1.235)
    }

    @Test func rejectsForeignFiles() {
        #expect(throws: CaptureFormat.ParseError.notACapture) {
            try CaptureFormat.decode(Data("{\"kind\":\"header\"}\n".utf8))
        }
        #expect(throws: CaptureFormat.ParseError.invalidLine(1)) {
            try CaptureFormat.decode(Data("not json\n".utf8))
        }
        #expect(throws: CaptureFormat.ParseError.empty) {
            try CaptureFormat.decode(Data())
        }
    }

    // MARK: Capturing transport (task 5.2)

    @Test func capturingTransportRecordsBytesAndEvents() async throws {
        let recorder = CaptureRecorder(environment: environment)
        let mock = MockTransport(identifier: "/dev/cu.mock", script: [.expect("$CNT\r\n"), .reply("$CNT,0\r\n")])
        let transport = CapturingTransport(mock, sink: recorder)
        try await transport.open()
        try await transport.write(Array("$CNT\r\n".utf8))
        _ = try await transport.readUntil(Array("\r\n".utf8), maxLength: 64, timeout: 1)
        await #expect(throws: LoggerError.self) {
            _ = try await transport.read(count: 1, timeout: 0.05)
        }
        await transport.close()

        let kinds = recorder.entries.map { $0.kind == "event" ? "event:\($0.name ?? "")" : $0.kind }
        #expect(kinds == ["event:open", "tx", "rx", "event:timeout", "event:close"])
        #expect(recorder.entries[2].bytes == Array("$CNT,0\r\n".utf8), "rx must include the terminator")
    }

    // MARK: Replay (task 5.3)

    /// Scenario "Wiedergabe eines erfolgreichen Auslesens".
    @Test func fixtureReplayProducesSameResult() async throws {
        let replay = try ReplayTransport(captureData: fixtureData())
        let recording = try await LineTestDriver(transport: replay).read()
        #expect(recording == expectedRecording)
        #expect(await replay.isFinished)
    }

    /// Scenario "Abweichung".
    @Test func deviationIsReportedWithPosition() async throws {
        let replay = try ReplayTransport(captureData: fixtureData())
        do {
            _ = try await LineTestDriver(transport: replay, secondIndex: 9).read()
            Issue.record("replay should fail")
        } catch let mismatch as ReplayMismatch {
            #expect(mismatch.position == 5)
            #expect(mismatch.expected == Array("$PT,1\r\n".utf8))
            #expect(mismatch.actual == Array("$PT,9\r\n".utf8))
            #expect(mismatch.description.contains("position 5"))
        }
    }

    @Test func recordedDialogCanBeReplayed() async throws {
        // Record a live (mock) dialog, then replay the capture: same result.
        let recorder = CaptureRecorder(environment: environment)
        let mock = MockTransport(identifier: "/dev/cu.live", script: [
            .expect("$CNT\r\n"), .reply("$CNT,2\r\n"),
            .expect("$PT,0\r\n"), .reply("$PT,0,51.5,8.5\r\n"),
            .expect("$PT,1\r\n"), .reply("$PT,1,51.6,8.6\r\n"),
        ])
        let live = try await LineTestDriver(transport: CapturingTransport(mock, sink: recorder)).read()
        let replayed = try await LineTestDriver(transport: ReplayTransport(captureData: recorder.encoded())).read()
        #expect(live == expectedRecording)
        #expect(replayed == live)
    }

    // MARK: Store (task 5.4)

    private func makeStore() -> (CaptureStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("captures-\(UUID().uuidString)")
        let suite = "gpsloader.tests.\(UUID().uuidString)"
        return (CaptureStore(directory: directory, defaultsSuiteName: suite), directory)
    }

    /// Scenario "Standardzustand".
    @Test func captureIsOffByDefaultAndPersists() {
        let (store, _) = makeStore()
        #expect(store.isEnabled == false)
        store.isEnabled = true
        #expect(store.isEnabled)
    }

    /// Scenario "Elfter Vorgang".
    @Test func keepsOnlyTheLastTenCaptures() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        var saved: [URL] = []
        for index in 0..<11 {
            let recorder = CaptureRecorder(environment: environment,
                                           startDate: Date(timeIntervalSince1970: 1_793_629_805 + Double(index)))
            recorder.record(.header(DiagnosticHeader(driver: "test")))
            saved.append(try store.save(recorder))
        }
        let remaining = store.captures().map(\.lastPathComponent)
        #expect(remaining.count == 10)
        #expect(!remaining.contains(saved[0].lastPathComponent), "the oldest capture must be deleted")
        #expect(remaining.contains(saved[1].lastPathComponent))
        #expect(store.latest()?.lastPathComponent == saved[10].lastPathComponent)
    }
}
