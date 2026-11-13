import DeviceDrivers
import Foundation
import Testing
import LoggerCore
@testable import BluetoothTransport

@Suite("Bluetooth RFCOMM transport")
struct RFCOMMStreamTests {
    private func stream() -> RFCOMMStream {
        RFCOMMStream(buffer: RFCOMMInputBuffer(), identifier: "bluetooth:test", interval: 1_000_000)
    }

    /// Scenario "Zeilen in mehreren Paketen": a line arriving in two RFCOMM packets is read as a whole.
    @Test func lineInTwoPackets() async throws {
        let stream = stream()
        stream.buffer.append(Array("$PMTKLOX,1,0,0011".utf8))
        Task {
            try? await Task.sleep(nanoseconds: 20_000_000)
            stream.buffer.append(Array("2233*00\r\n$GP".utf8))
        }
        let line = try await stream.readUntil([0x0D, 0x0A], maxLength: 256, timeout: 1)
        #expect(String(decoding: line, as: UTF8.self) == "$PMTKLOX,1,0,00112233*00")
        #expect(try await stream.read(count: 3, timeout: 1) == Array("$GP".utf8))
    }

    /// Scenario "Gerät trennt die Verbindung": a waiting read fails with an error, not with a timeout.
    @Test func deviceClosesTheChannel() async {
        let stream = stream()
        Task {
            try? await Task.sleep(nanoseconds: 20_000_000)
            stream.buffer.close(reason: "the device closed the Bluetooth connection")
        }
        await #expect(throws: LoggerError(.deviceNotFound, detail: "bluetooth:test: the device closed the Bluetooth connection")) {
            try await stream.readUntil([0x0D, 0x0A], maxLength: 256, timeout: 5)
        }
    }

    @Test func dataBeforeCloseIsStillRead() async throws {
        let stream = stream()
        stream.buffer.append(Array("END\r\n".utf8))
        stream.buffer.close(reason: "closed")
        #expect(try await stream.readUntil([0x0D, 0x0A], maxLength: 16, timeout: 1) == Array("END".utf8))
    }

    @Test func inactivityTimeout() async {
        let stream = stream()
        await #expect(throws: LoggerError(.timeout, detail: "bluetooth:test: no answer")) {
            try await stream.read(count: 1, timeout: 0.05)
        }
    }

    @Test func lineTooLong() async {
        let stream = stream()
        stream.buffer.append([UInt8](repeating: 0x41, count: 40))
        await #expect(throws: LoggerError.self) {
            try await stream.readUntil([0x0D, 0x0A], maxLength: 16, timeout: 1)
        }
    }

    @Test func factoryUsesNamesAndService() throws {
        let entry = try #require(DeviceCatalog.entry(withID: "gns2000.gns-2000"))
        let factory = IOBluetoothTransportFactory()
        #expect(factory.resourceKey(for: entry) == "bluetooth:GNS 2000")
        let transport = try #require(factory.makeTransport(for: entry) as? RFCOMMTransport)
        #expect(transport.deviceNames == ["GNS 2000", "GNS 2000 plus"] && transport.serviceName == "GNS GPS")
        #expect(transport.identifier == "bluetooth:GNS 2000")
    }
}
