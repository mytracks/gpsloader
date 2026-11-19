import CoreBluetooth
import DeviceDrivers
import Foundation
import IOBluetooth
import LoggerCore

/// The IOBluetooth side of a connection: finds the paired device, queries SDP and opens the RFCOMM channel
/// of a service (spec `bluetooth-transport`). IOBluetooth calls its delegates on the main run loop, so the
/// handle is main-actor isolated; received data goes to a lock-protected buffer.
@MainActor
final class RFCOMMChannelHandle: NSObject {
    let buffer: RFCOMMInputBuffer
    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    /// The one pending asynchronous step (connection, SDP query, channel opening).
    private var pending: CheckedContinuation<Void, Error>?
    /// Identifies the pending step, so that the timer of an earlier step cannot end a later one.
    private var pendingStep = 0

    init(buffer: RFCOMMInputBuffer) {
        self.buffer = buffer
    }

    /// Opens the RFCOMM channel of `serviceName` on the first paired device named like one of `deviceNames`.
    func open(deviceNames: [String], serviceName: String, timeout: TimeInterval) async throws {
        if [.denied, .restricted].contains(CBManager.authorization) {
            throw LoggerError(.deviceNotFound, detail: "Bluetooth access is not allowed for \(ProductName.name). "
                + "Allow it in System Settings > Privacy & Security > Bluetooth.")
        }
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        guard let device = paired.first(where: { deviceNames.contains($0.name ?? "") }) else {
            throw LoggerError(.deviceNotFound, detail: "\(deviceNames.joined(separator: " / ")) is not paired. "
                + "Pair it in System Settings > Bluetooth.")
        }
        self.device = device
        let deadline = Date().addingTimeInterval(timeout)
        if device.isConnected() { device.closeConnection() }

        try await step(until: deadline, "connection") { device.openConnection(self) }
        try await step(until: deadline, "SDP query") { device.performSDPQuery(self) }

        let services = (device.services as? [IOBluetoothSDPServiceRecord]) ?? []
        var channelID: BluetoothRFCOMMChannelID = 0
        guard let service = services.first(where: { $0.getServiceName() == serviceName }),
              service.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else {
            throw LoggerError(.deviceNotFound, detail: "\(device.name ?? "Device") has no service \"\(serviceName)\"")
        }
        try await step(until: deadline, "RFCOMM channel") {
            var channel: IOBluetoothRFCOMMChannel?
            let result = device.openRFCOMMChannelAsync(&channel, withChannelID: channelID, delegate: self)
            self.channel = channel
            return result
        }
    }

    /// Starts an asynchronous IOBluetooth operation and waits for its delegate callback, the deadline or cancellation.
    private func step(until deadline: Date, _ name: String, _ start: () -> IOReturn) async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                pending = continuation
                pendingStep += 1
                let current = pendingStep
                let result = start()
                guard result == kIOReturnSuccess else {
                    finish(.failure(LoggerError(.deviceNotFound, detail: String(format: "Bluetooth %@ failed: 0x%08x", name, result))))
                    return
                }
                let delay = max(deadline.timeIntervalSinceNow, 0)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    guard let self, self.pendingStep == current else { return }
                    self.finish(.failure(LoggerError(.timeout, detail: "Bluetooth \(name): no answer")))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
    }

    /// Resumes the pending step once; later calls (e.g. the timeout after success) are ignored.
    private func finish(_ result: Result<Void, Error>) {
        guard let continuation = pending else { return }
        pending = nil
        continuation.resume(with: result)
    }

    private func complete(_ status: IOReturn, _ name: String) {
        finish(status == kIOReturnSuccess ? .success(())
            : .failure(LoggerError(.deviceNotFound, detail: String(format: "Bluetooth %@ failed: 0x%08x", name, status))))
    }

    /// Writes in pieces of at most the channel's MTU.
    func write(_ bytes: [UInt8]) throws {
        guard let channel else { throw LoggerError(.deviceNotFound, detail: "Bluetooth channel is not open") }
        let mtu = max(Int(channel.getMTU()), 1)
        var data = bytes
        for start in stride(from: 0, to: data.count, by: mtu) {
            let length = min(mtu, data.count - start)
            let result = data.withUnsafeMutableBytes { channel.writeSync($0.baseAddress! + start, length: UInt16(length)) }
            guard result == kIOReturnSuccess else {
                throw LoggerError(.deviceNotFound, detail: String(format: "Bluetooth write failed: 0x%08x", result))
            }
        }
    }

    func close() {
        finish(.failure(CancellationError()))
        channel?.setDelegate(nil)
        channel?.close()
        channel = nil
        device?.closeConnection()
        device = nil
        buffer.close(reason: "Bluetooth connection closed")
    }
}

extension RFCOMMChannelHandle: @preconcurrency IOBluetoothDeviceAsyncCallbacks {
    func remoteNameRequestComplete(_ device: IOBluetoothDevice!, status: IOReturn) {}

    func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        complete(status, "connection")
    }

    func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        complete(status, "SDP query")
    }
}

extension RFCOMMChannelHandle: @preconcurrency IOBluetoothRFCOMMChannelDelegate {
    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!,
                           length dataLength: Int) {
        buffer.append(UnsafeRawBufferPointer(start: dataPointer, count: dataLength))
    }

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        complete(error, "RFCOMM channel")
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        buffer.close(reason: "the device closed the Bluetooth connection")
        finish(.failure(LoggerError(.deviceNotFound, detail: "the device closed the Bluetooth connection")))
    }
}

/// `ByteTransport` over a Bluetooth RFCOMM channel (spec `bluetooth-transport`).
public final class RFCOMMTransport: ByteTransport, @unchecked Sendable {
    public let identifier: String
    let deviceNames: [String]
    let serviceName: String
    static let openTimeout: TimeInterval = 20
    private let buffer = RFCOMMInputBuffer()
    private let stream: RFCOMMStream
    private let lock = NSLock()
    private var handle: RFCOMMChannelHandle?

    public init(deviceNames: [String], serviceName: String) {
        self.deviceNames = deviceNames
        self.serviceName = serviceName
        identifier = "bluetooth:\(deviceNames.first ?? serviceName)"
        stream = RFCOMMStream(buffer: buffer, identifier: identifier)
    }

    public func open() async throws {
        let buffer = buffer
        let handle = await MainActor.run { RFCOMMChannelHandle(buffer: buffer) }
        lock.withLock { self.handle = handle }
        do {
            try await handle.open(deviceNames: deviceNames, serviceName: serviceName, timeout: Self.openTimeout)
        } catch {
            await handle.close()
            throw error
        }
    }

    public func write(_ bytes: [UInt8]) async throws {
        guard let handle = lock.withLock({ handle }) else {
            throw LoggerError(.deviceNotFound, detail: "\(identifier): not open")
        }
        try await handle.write(bytes)
    }

    public func read(count: Int, timeout: TimeInterval) async throws -> [UInt8] {
        try await stream.read(count: count, timeout: timeout)
    }

    public func readUntil(_ terminator: [UInt8], maxLength: Int, timeout: TimeInterval) async throws -> [UInt8] {
        try await stream.readUntil(terminator, maxLength: maxLength, timeout: timeout)
    }

    public func close() async {
        guard let handle = lock.withLock({ () -> RFCOMMChannelHandle? in defer { self.handle = nil }; return self.handle }) else {
            return
        }
        await handle.close()
    }
}

/// Creates RFCOMM transports for catalog entries with the connection kind `.bluetooth`.
public struct IOBluetoothTransportFactory: BluetoothTransportFactory {
    public init() {}

    public func resourceKey(for entry: DeviceEntry) -> String {
        if case .bluetooth(let names, _) = entry.connection { return "bluetooth:\(names.first ?? entry.id)" }
        return "bluetooth:\(entry.id)"
    }

    public func makeTransport(for entry: DeviceEntry) -> any ByteTransport {
        guard case .bluetooth(let names, let service) = entry.connection else {
            return RFCOMMTransport(deviceNames: [], serviceName: "")
        }
        return RFCOMMTransport(deviceNames: names, serviceName: service)
    }
}
