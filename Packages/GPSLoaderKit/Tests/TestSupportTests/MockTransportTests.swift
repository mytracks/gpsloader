import Foundation
import Testing
import LoggerCore
@testable import TestSupport

@Suite("MockTransport")
struct MockTransportTests {
    @Test func answersExpectedCommand() async throws {
        let mock = MockTransport(script: [
            .expect("PING\r\n"),
            .reply("PONG\r\n"),
        ])
        try await mock.open()
        try await mock.write(Array("PING\r\n".utf8))
        let line = try await mock.readUntil(Array("\r\n".utf8), maxLength: 100, timeout: 1)
        #expect(line == Array("PONG".utf8))
        #expect(await mock.isScriptFinished)
    }

    @Test func initialRepliesAreSentOnOpen() async throws {
        let mock = MockTransport(script: [.reply([0x01, 0x02, 0x03])])
        try await mock.open()
        #expect(try await mock.read(count: 3, timeout: 1) == [0x01, 0x02, 0x03])
    }

    /// Scenario "Unexpected command in the mock" (spec serial-transport).
    @Test func unexpectedCommandNamesExpectedAndActual() async throws {
        let mock = MockTransport(script: [.expect([0x93, 0x01]), .reply([0x93])])
        try await mock.open()
        do {
            try await mock.write([0x93, 0x0B])
            Issue.record("write should have failed")
        } catch let mismatch as MockTransportMismatch {
            #expect(mismatch.description.contains("93 01"))
            #expect(mismatch.description.contains("93 0B"))
        }
        #expect(await mock.mismatches.count == 1)
    }

    @Test func silenceLeadsToTimeout() async throws {
        let mock = MockTransport(script: [.expect("HELLO")])
        try await mock.open()
        try await mock.write(Array("HELLO".utf8))
        await #expect(throws: LoggerError(.timeout, detail: "/dev/cu.mock: no data for 0.1 s")) {
            _ = try await mock.read(count: 1, timeout: 0.1)
        }
    }

    @Test func delayedReplyArrives() async throws {
        let mock = MockTransport(script: [.expect("A"), .reply("B", delay: 0.05)])
        try await mock.open()
        try await mock.write(Array("A".utf8))
        #expect(try await mock.read(count: 1, timeout: 1) == Array("B".utf8))
    }

    @Test func cancellationStopsRead() async throws {
        let mock = MockTransport(script: [])
        try await mock.open()
        let task = Task { try await mock.read(count: 1, timeout: 60) }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        await #expect(throws: LoggerError(.cancelled)) { try await task.value }
    }

    @Test func hexHelpersRoundTrip() {
        let bytes: [UInt8] = [0x93, 0x0A, 0xFF, 0x00]
        #expect(bytes.hexString == "93 0A FF 00")
        #expect([UInt8](hexString: "93 0a ff 00") == bytes)
        #expect([UInt8](hexString: "9") == nil)
        #expect(Array("A\r\n\u{01}".utf8).printableASCII == "A\\r\\n.")
    }
}
