import Darwin
import Foundation
import Testing
import LoggerCore
@testable import SerialTransport

/// Spec `serial-transport`, "Change the baud rate" (change device-mode).
@Suite("SerialPort baud rate", .serialized)
struct BaudRateTests {
    /// Scenario "Switch after the negotiation".
    @Test func switchesTheRateOfTheOpenPort() async throws {
        let pty = try PseudoTerminal()
        let port = SerialPort(path: pty.path, baudRate: 9600)
        try await port.open()
        try await port.setBaudRate(115_200)
        // Still usable after the switch.
        pty.deviceSend([0x41, 0x42])
        #expect(try await port.read(count: 2, timeout: 1) == [0x41, 0x42])
        #expect(await port.baudRate == 115_200)
        #expect(await port.configuredSpeed() == 115_200)
        var attributes = pty.slaveAttributes()
        #expect(cfgetospeed(&attributes) == speed_t(115_200))
        await port.close()
    }

    @Test func unsupportedRateIsRejected() async throws {
        let pty = try PseudoTerminal()
        let port = SerialPort(path: pty.path, baudRate: 9600)
        try await port.open()
        await #expect(throws: LoggerError(.protocolError, detail: "Unsupported baud rate 12345")) {
            try await port.setBaudRate(12_345)
        }
        await port.close()
    }

    @Test func discardInputDropsPendingBytes() async throws {
        let pty = try PseudoTerminal()
        let port = SerialPort(path: pty.path, baudRate: 9600)
        try await port.open()
        pty.deviceSend([1, 2, 3])
        #expect(try await port.read(count: 1, timeout: 1) == [1])
        await port.discardInput()
        pty.deviceSend([9])
        #expect(try await port.read(count: 1, timeout: 1) == [9])
        await port.close()
    }
}
