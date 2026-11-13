// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import GPSLoggerKit
@testable import GPSLoggerKitGPL

/// A simulated MTK logger (spec `mtk-device`) answering the PMTK commands of mtk_logger.cc.
final class MTKSimulator: @unchecked Sendable {
    private let lock = NSLock()
    var memory: [UInt8]
    var usedBytes: Int?
    var model = "M-241"
    var logStatus = 2  // auto log enabled
    var erased = false
    var enabledAgain = false
    var rejectFirstRead = false
    var lines: [String] = []

    init(memory: [UInt8], usedBytes: Int?) {
        self.memory = memory
        self.usedBytes = usedBytes
    }

    static func sentence(_ body: String) -> String { MTKDevice.sentence(body) }

    func respond(_ written: [UInt8]) -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }
        let text = String(decoding: written, as: UTF8.self)
        lines.append(text)
        let noise = "$GPGGA,120000.000,5000.0000,N,00800.0000,E,1,8,1.0,100.0,M,47.0,M,,*41\r\n"
        let body = text.dropFirst().prefix { $0 != "*" }
        var reply = noise
        switch body {
        case "PMTK605": reply += Self.sentence("PMTK705,AXN_1.0-B_1.3_C01,0005,\(model),1.0")
        case "PHLX810": reply += Self.sentence("PHLX852,GR245")
        case "PHLX826": reply += "$PHLX859*38\r\n"
        case "PHLX827": reply += "$PHLX860*32\r\n"
        case "PMTK182,2,7": reply += Self.sentence("PMTK001,182,2,3") + Self.sentence("PMTK182,3,7,\(logStatus)")
        case "PMTK182,2,2": reply += Self.sentence("PMTK182,3,2,0000003F")
        case "PMTK182,5": reply += Self.sentence("PMTK001,182,5,3")
        case "PMTK182,4": enabledAgain = true; reply += Self.sentence("PMTK001,182,4,3")
        case "PMTK182,6,1": erased = true; reply += Self.sentence("PMTK001,182,6,3")
        case "PMTK182,2,8":
            if let usedBytes { reply += Self.sentence(String(format: "PMTK182,3,8,%08X", usedBytes)) }
        default:
            if body.hasPrefix("PMTK182,7,") {
                if rejectFirstRead {
                    rejectFirstRead = false
                    return Array((reply + Self.sentence("PMTK001,182,7,2")).utf8)
                }
                let fields = body.split(separator: ",")
                let address = Int(fields[2], radix: 16)!, size = Int(fields[3], radix: 16)!
                // The whole block comes in one line (the source sizes its line buffer as 2 * block size + 32).
                let bytes = (address..<(address + size)).map { $0 < memory.count ? memory[$0] : 0xFF }
                reply += Self.sentence(String(format: "PMTK182,8,%08X,", address) + bytes.map { String(format: "%02X", $0) }.joined())
                reply += Self.sentence("PMTK001,182,7,3")
            }
        }
        return Array(reply.utf8)
    }
}

/// Logger memory with a full first block (padding shorter than one answer chunk) and a second block,
/// as a logger writes it; a download stops at the first block of 0xFF only.
private func fullMemory() -> MTKTestDump {
    var dump = MTKTestDump(mask: MTKTestDump.Bit.basic)
    dump.info(0x07, 0x0106)
    var k: UInt32 = 0
    while dump.bytes.count % 0x10000 < 0xFF00 {
        dump.record(MTKTestDump.Record(time: MTKTestDump.start + k, latitude: 50 + Double(k) * 0.00001))
        k += 1
    }
    dump.endBlock()
    for j in 0..<3 { dump.record(MTKTestDump.Record(time: MTKTestDump.start + 10_000 + UInt32(j), latitude: 51)) }
    dump.finish()
    return dump
}

private func connection(_ simulator: MTKSimulator) -> SimulatedDevice {
    SimulatedDevice(baudRate: 115_200) { written, _ in simulator.respond(written) }
}

@Suite("MTK device")
struct MTKDeviceTests {
    @Test func sentenceChecksum() {
        #expect(MTKDevice.sentence("PMTK182,2,7") == MTKDevice.logStatus)
        #expect(MTKDevice.sentence("PMTK605") == "$PMTK605*31\r\n")
        #expect(MTKDevice.sentence("PMTK182,6,1") == MTKDevice.logErase)
    }

    /// Scenario "Auslesen": same recording as the dump decoder, logging enabled again.
    @Test func readsTheMemory() async throws {
        let dump = fullMemory()
        let simulator = MTKSimulator(memory: dump.bytes, usedBytes: 0x10300)
        let progress = ProgressLog()
        let recording = try await MTKDevice(model: .mtk).read(connection(simulator),
                                                               DeviceReporter(progress: { done, _, _ in progress.add(done) }))
        let expected = try MTKDump.read([FileInput(name: "MTK", data: dump.data)], device: .mtk).recording
        #expect(recording.trackPointCount == expected.trackPointCount && recording.trackPointCount > 2000)
        #expect(recording.tracks.last?.segments.last?.points.last?.latitude == 51)
        #expect(simulator.enabledAgain)
        #expect(!progress.values.isEmpty)
    }

    /// Scenario "Belegung unbekannt": the end of the data is found by scanning 64 KiB blocks.
    @Test func unknownUsage() async throws {
        let dump = fullMemory()
        let simulator = MTKSimulator(memory: dump.bytes, usedBytes: nil)
        let recording = try await MTKDevice(model: .mtk).read(connection(simulator), DeviceReporter())
        #expect(recording.trackPointCount == (try MTKDump.read([FileInput(name: "x", data: dump.data)], device: .mtk)).recording.trackPointCount)
    }

    /// Scenario "Holux M-241".
    @Test func holux() async throws {
        let simulator = MTKSimulator(memory: MTKTestDump.m241Fixture().bytes, usedBytes: 0x300)
        let device = MTKDevice(model: .holux)
        #expect(device.baudRate == 38400)
        let recording = try await device.read(connection(simulator), DeviceReporter())
        #expect(recording.trackPointCount == 4 && recording.waypoints.count == 1)
    }

    /// GR-245: the Holux handshake is sent before and after.
    @Test func gr245Handshake() async throws {
        let simulator = MTKSimulator(memory: MTKTestDump.m241Fixture().bytes, usedBytes: 0x300)
        simulator.model = "GR-245"
        _ = try await MTKDevice(model: .holux).read(connection(simulator), DeviceReporter())
        #expect(simulator.lines.contains("$PHLX810*35\r\n") && simulator.lines.contains("$PHLX827*31\r\n"))
    }

    /// Scenario "Abgelehnter Block": a negative acknowledgement repeats the request.
    @Test func rejectedBlockIsRetried() async throws {
        let simulator = MTKSimulator(memory: MTKTestDump.mtkFixture().bytes, usedBytes: 0x300)
        simulator.rejectFirstRead = true
        let recording = try await MTKDevice(model: .mtk).read(connection(simulator), DeviceReporter())
        #expect(recording.trackPointCount == 4)  // block 0 of the fixture; its long 0xFF padding ends the download
    }

    /// Scenario "Kein MTK-Logger".
    @Test func notAnMTKLogger() async {
        let silent = SimulatedDevice { _, _ in Array("$GPRMC,noise*00\r\n".utf8) }
        await #expect(throws: DeviceProtocolError("This is not an MTK based logger (or it is switched off)")) {
            try await MTKDevice(model: .mtk).read(silent, DeviceReporter())
        }
    }

    /// Scenario "Speicher löschen".
    @Test func erase() async throws {
        let simulator = MTKSimulator(memory: [], usedBytes: 0)
        try await MTKDevice(model: .mtk).erase(connection(simulator), DeviceReporter())
        #expect(simulator.erased && simulator.enabledAgain)
    }
}
