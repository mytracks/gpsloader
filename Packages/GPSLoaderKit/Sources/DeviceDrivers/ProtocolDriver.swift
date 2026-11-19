import DiagnosticCapture
import Foundation
import GPSLoggerKit
import GPSLoggerKitGPL
import LoggerCore
import SerialTransport

/// Runs a protocol of GPSLoggerKit or GPSLoggerKitGPL as a session driver (spec `device-mode`, "Connecting the drivers").
public struct ProtocolDriver: LoggerDriver {
    public let entry: DeviceEntry
    /// Serial port path; `nil` for HID and Bluetooth devices.
    public let portPath: String?
    let hidFactory: (any HIDConnectionFactory)?
    let bluetoothFactory: (any BluetoothTransportFactory)?
    /// Creates the transport for a serial port; replaceable in tests.
    let makeTransport: @Sendable (_ path: String, _ baudRate: Int) -> any ByteTransport
    /// Reference time of the week rollover correction; replaceable in tests.
    let now: @Sendable () -> Date

    public init(entry: DeviceEntry, portPath: String?, hidFactory: (any HIDConnectionFactory)? = nil,
                bluetoothFactory: (any BluetoothTransportFactory)? = nil) {
        self.init(entry: entry, portPath: portPath, hidFactory: hidFactory, bluetoothFactory: bluetoothFactory) { path, baudRate in
            SerialPort(path: path, baudRate: baudRate)
        }
    }

    init(entry: DeviceEntry, portPath: String?, hidFactory: (any HIDConnectionFactory)?,
         bluetoothFactory: (any BluetoothTransportFactory)? = nil, now: @escaping @Sendable () -> Date = { Date() },
         makeTransport: @escaping @Sendable (_ path: String, _ baudRate: Int) -> any ByteTransport) {
        self.entry = entry
        self.portPath = portPath
        self.hidFactory = hidFactory
        self.bluetoothFactory = bluetoothFactory
        self.now = now
        self.makeTransport = makeTransport
    }

    public var descriptor: DriverDescriptor {
        DriverDescriptor(id: entry.driverID, name: entry.name, eraseSupport: entry.eraseSupport)
    }

    public var resourceKey: String {
        if let portPath { return portPath }
        if case .bluetooth = entry.connection {
            return bluetoothFactory?.resourceKey(for: entry) ?? "bluetooth:\(entry.id)"
        }
        return hidFactory?.resourceKey(for: entry) ?? "hid:\(entry.id)"
    }

    /// Reads the device and corrects GPS week rollovers (spec `device-mode`,
    /// "GPS week rollover correction when reading").
    public func read(_ context: DriverContext) async throws -> Recording {
        let recording = try await run(context) { proto, connection, reporter in
            try await proto.read(connection, reporter)
        }
        return RecordingProcessing.correctingWeekRollover(recording, reference: now())
    }

    public func erase(_ context: DriverContext) async throws {
        _ = try await run(context) { proto, connection, reporter in
            try await proto.erase(connection, reporter)
            return Recording()
        }
    }

    private func run(_ context: DriverContext,
                     _ body: @Sendable (any DeviceProtocol, any DeviceConnection, DeviceReporter) async throws -> Recording)
        async throws -> Recording {
        let reporter = DeviceReporter(
            progress: { completed, total, step in
                context.progress(.determinate(completed: completed, total: total, step: step))
            },
            step: { context.progress(.indeterminate(step: $0)) },
            activity: { context.activity() })
        let proto = entry.makeProtocol()

        let connection: any DeviceConnection
        let close: @Sendable () async -> Void
        switch entry.connection {
        case .serial(let baudRate):
            guard let portPath else { throw LoggerError(.deviceNotFound, detail: "No port selected") }
            let port = makeTransport(portPath, baudRate)
            let transport = CapturingTransport(port, sink: context.diagnostics)
            try await transport.open()
            connection = ConnectionBridge(transport: transport, port: port, activity: context.activity)
            close = { await transport.close() }
        case .hid:
            guard let hidFactory else { throw LoggerError(.deviceNotFound, detail: "USB HID is not available") }
            (connection, close) = try await hidFactory.open(entry, diagnostics: context.diagnostics)
        case .bluetooth:
            guard let bluetoothFactory else { throw LoggerError(.deviceNotFound, detail: "Bluetooth is not available") }
            let device = bluetoothFactory.makeTransport(for: entry)
            let transport = CapturingTransport(device, sink: context.diagnostics)
            try await transport.open()
            connection = ConnectionBridge(transport: transport, port: device, activity: context.activity)
            close = { await transport.close() }
        }

        do {
            let result = try await body(proto, connection, reporter)
            await close()
            return result
        } catch let error as DeviceProtocolError {
            await close()
            throw LoggerError(.protocolError, detail: error.message)
        } catch {
            await close()
            throw error
        }
    }
}

/// `DeviceConnection` on top of a `ByteTransport`; baud rate and input flush go to the serial port.
struct ConnectionBridge: DeviceConnection {
    let transport: any ByteTransport
    let port: any ByteTransport
    let activity: @Sendable () -> Void

    func write(_ bytes: [UInt8]) async throws {
        try await transport.write(bytes)
    }

    func read(count: Int, timeout: TimeInterval) async throws -> [UInt8] {
        let bytes = try await transport.read(count: count, timeout: timeout)
        activity()
        return bytes
    }

    func readUntil(_ terminator: [UInt8], maxLength: Int, timeout: TimeInterval) async throws -> [UInt8] {
        let bytes = try await transport.readUntil(terminator, maxLength: maxLength, timeout: timeout)
        activity()
        return bytes
    }

    func discardInput() async {
        if let serial = port as? SerialPort { await serial.discardInput() }
    }

    func setBaudRate(_ rate: Int) async throws {
        if let serial = port as? SerialPort { try await serial.setBaudRate(rate) }
    }
}
