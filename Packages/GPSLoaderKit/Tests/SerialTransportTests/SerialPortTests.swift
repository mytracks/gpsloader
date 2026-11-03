import Darwin
import Foundation
import Testing
import LoggerCore
@testable import SerialTransport

/// Serial port tests against pseudo terminals (spec `serial-transport`).
@Suite("SerialPort", .serialized)
struct SerialPortTests {
    // MARK: Open and configure

    /// Scenario "Öffnen mit 115200 Baud".
    @Test func opensWith115200RawMode() async throws {
        let pty = try PseudoTerminal()
        let port = SerialPort(path: pty.path, baudRate: 115_200)
        try await port.open()
        defer { Task { await port.close() } }

        var attributes = pty.slaveAttributes()
        #expect(cfgetospeed(&attributes) == speed_t(115_200))
        #expect(attributes.c_cflag & tcflag_t(CSIZE) == tcflag_t(CS8))
        #expect(attributes.c_cflag & tcflag_t(PARENB) == 0)
        #expect(attributes.c_cflag & tcflag_t(CSTOPB) == 0)
        #expect(attributes.c_cflag & tcflag_t(CRTSCTS) == 0)
        #expect(attributes.c_lflag & tcflag_t(ICANON) == 0)
        #expect(await port.isOpen)
    }

    @Test(arguments: [4800, 9600, 19200, 38400, 57600, 115_200])
    func supportsRequiredBaudRates(baud: Int) async throws {
        let pty = try PseudoTerminal()
        let port = SerialPort(path: pty.path, baudRate: baud)
        try await port.open()
        var attributes = pty.slaveAttributes()
        #expect(cfgetospeed(&attributes) == speed_t(baud))
        await port.close()
    }

    /// Scenario "Port existiert nicht".
    @Test func missingPortIsDeviceNotFound() async {
        let port = SerialPort(path: "/dev/cu.gpsloader-does-not-exist", baudRate: 9600)
        await #expect {
            try await port.open()
        } throws: { error in
            (error as? LoggerError)?.kind == .deviceNotFound
        }
    }

    /// Scenario "Port bereits geöffnet".
    @Test func secondOpenIsPortBusy() async throws {
        let pty = try PseudoTerminal()
        let first = SerialPort(path: pty.path, baudRate: 9600)
        try await first.open()
        let second = SerialPort(path: pty.path, baudRate: 9600)
        await #expect {
            try await second.open()
        } throws: { error in
            (error as? LoggerError)?.kind == .portBusy
        }
        await first.close()
        // After closing, the port can be opened again.
        try await second.open()
        await second.close()
    }

    // MARK: Writing

    /// Scenario "Befehl senden".
    @Test func writesAllBytes() async throws {
        let pty = try PseudoTerminal()
        let port = SerialPort(path: pty.path, baudRate: 9600)
        try await port.open()
        let command: [UInt8] = Array(0..<16)
        try await port.write(command)
        #expect(pty.deviceReceive(count: 16) == command)
        await port.close()
    }

    // MARK: Reading (task 3.2)

    /// Scenario "Zeile lesen".
    @Test func readsLineWithoutTerminator() async throws {
        let pty = try PseudoTerminal()
        let port = SerialPort(path: pty.path, baudRate: 115_200)
        try await port.open()
        pty.deviceSend("$TEST,1,2\r\n$NEXT\r\n")
        let line = try await port.readUntil(Array("\r\n".utf8), maxLength: 256, timeout: 1)
        #expect(line == Array("$TEST,1,2".utf8))
        let next = try await port.readUntil(Array("\r\n".utf8), maxLength: 256, timeout: 1)
        #expect(next == Array("$NEXT".utf8))
        await port.close()
    }

    /// Scenario "Daten in Teilstücken".
    @Test func readsCountAcrossChunks() async throws {
        let pty = try PseudoTerminal()
        let port = SerialPort(path: pty.path, baudRate: 115_200)
        try await port.open()
        let payload = (0..<4096).map { UInt8($0 % 256) }
        let sender = Task.detached {
            for start in stride(from: 0, to: payload.count, by: 512) {
                pty.deviceSend(Array(payload[start..<min(start + 512, payload.count)]))
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        let received = try await port.read(count: 4096, timeout: 1)
        await sender.value
        #expect(received == payload)
        await port.close()
    }

    /// Scenario "Gerät schweigt".
    @Test func silenceIsTimeout() async throws {
        let pty = try PseudoTerminal()
        let port = SerialPort(path: pty.path, baudRate: 9600)
        try await port.open()
        let start = Date()
        await #expect {
            _ = try await port.read(count: 1, timeout: 0.3)
        } throws: { error in
            (error as? LoggerError)?.kind == .timeout
        }
        #expect(Date().timeIntervalSince(start) >= 0.3)
        // A timeout keeps the port open, the driver may retry.
        #expect(await port.isOpen)
        await port.close()
    }

    @Test func lineWithoutTerminatorBeyondMaxLengthIsProtocolError() async throws {
        let pty = try PseudoTerminal()
        let port = SerialPort(path: pty.path, baudRate: 9600)
        try await port.open()
        pty.deviceSend(String(repeating: "x", count: 64))
        await #expect {
            _ = try await port.readUntil(Array("\r\n".utf8), maxLength: 32, timeout: 1)
        } throws: { error in
            (error as? LoggerError)?.kind == .protocolError
        }
        await port.close()
    }

    /// Scenario "Abbruch während des Lesens".
    @Test func cancellationEndsReadAndClosesPort() async throws {
        let pty = try PseudoTerminal()
        let port = SerialPort(path: pty.path, baudRate: 9600)
        try await port.open()
        let reader = Task { try await port.read(count: 1, timeout: 60) }
        try await Task.sleep(nanoseconds: 100_000_000)
        let cancelledAt = Date()
        reader.cancel()
        await #expect {
            _ = try await reader.value
        } throws: { error in
            (error as? LoggerError)?.kind == .cancelled
        }
        #expect(Date().timeIntervalSince(cancelledAt) < 0.5)
        #expect(await !port.isOpen)
    }

    // MARK: Disconnect (task 3.3)

    /// Scenario "Gerät wird abgezogen".
    @Test func hangUpEndsReadAndReleasesPort() async throws {
        let pty = try PseudoTerminal()
        let port = SerialPort(path: pty.path, baudRate: 9600)
        try await port.open()
        pty.releaseSlave()
        let reader = Task { try await port.read(count: 10, timeout: 5) }
        try await Task.sleep(nanoseconds: 100_000_000)
        pty.hangUp()
        await #expect {
            _ = try await reader.value
        } throws: { error in
            (error as? LoggerError)?.kind == .deviceNotFound
        }
        #expect(await !port.isOpen)
    }
}
