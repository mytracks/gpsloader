import DeviceDrivers
import Foundation
import GPSLoggerKit
import GPSLoggerKitGPL
import IOKit.hid
import LoggerCore

/// Bytes of input reports, filled on the HID dispatch queue and read by the connection.
final class HIDInputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: [UInt8] = []

    func append(_ data: UnsafeBufferPointer<UInt8>) {
        lock.lock()
        bytes += data
        lock.unlock()
    }

    func take(_ count: Int) -> [UInt8]? {
        lock.lock()
        defer { lock.unlock() }
        guard bytes.count >= count else { return nil }
        let result = Array(bytes.prefix(count))
        bytes.removeFirst(count)
        return result
    }

    func removeAll() {
        lock.lock()
        bytes.removeAll()
        lock.unlock()
    }

    var available: Int {
        lock.lock()
        defer { lock.unlock() }
        return bytes.count
    }
}

/// An opened IOHIDDevice. Writes are output reports (`SET_REPORT`, the control transfer
/// 0x21/0x09/0x0200 of igotu2gpx), reads come from input reports (interrupt endpoint).
final class HIDDeviceHandle: @unchecked Sendable {
    let device: IOHIDDevice
    let buffer = HIDInputBuffer()
    let queue = DispatchQueue(label: "gpsloader.hid")
    private var reportBuffer: UnsafeMutablePointer<UInt8>
    private let reportSize: Int

    init(device: IOHIDDevice) throws {
        self.device = device
        reportSize = (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int).map { max($0, 8) } ?? 64
        reportBuffer = .allocate(capacity: reportSize)
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard result == kIOReturnSuccess else {
            reportBuffer.deallocate()
            throw LoggerError(.portBusy, detail: String(format: "IOHIDDeviceOpen: 0x%08x", result))
        }
        let context = Unmanaged.passUnretained(buffer).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, reportSize, { context, result, _, _, _, report, length in
            guard let context, result == kIOReturnSuccess else { return }
            let buffer = Unmanaged<HIDInputBuffer>.fromOpaque(context).takeUnretainedValue()
            buffer.append(UnsafeBufferPointer(start: report, count: length))
        }, context)
        IOHIDDeviceSetDispatchQueue(device, queue)
        IOHIDDeviceActivate(device)
    }

    func write(_ chunk: [UInt8]) throws {
        let result = chunk.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, $0.baseAddress!, $0.count)
        }
        guard result == kIOReturnSuccess else {
            throw LoggerError(.deviceNotFound, detail: String(format: "IOHIDDeviceSetReport: 0x%08x", result))
        }
    }

    func close() {
        IOHIDDeviceCancel(device)
        queue.sync {}
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        reportBuffer.deallocate()
    }
}

/// `DeviceConnection` over USB HID; records all bytes in the diagnostic capture.
struct HIDDeviceConnection: DeviceConnection {
    let handle: HIDDeviceHandle
    let source: String
    let diagnostics: any DiagnosticSink
    static let reportLength = 8

    func write(_ bytes: [UInt8]) async throws {
        diagnostics.record(.transmitted(source: source, bytes: bytes))
        for start in stride(from: 0, to: bytes.count, by: Self.reportLength) {
            var chunk = Array(bytes[start..<min(start + Self.reportLength, bytes.count)])
            chunk += [UInt8](repeating: 0, count: Self.reportLength - chunk.count)
            try handle.write(chunk)
        }
    }

    func read(count: Int, timeout: TimeInterval) async throws -> [UInt8] {
        var deadline = Date().addingTimeInterval(timeout)
        var available = handle.buffer.available
        while true {
            if let bytes = handle.buffer.take(count) {
                diagnostics.record(.received(source: source, bytes: bytes))
                return bytes
            }
            if Task.isCancelled { throw LoggerError(.cancelled) }
            let now = handle.buffer.available
            if now != available {  // inactivity timeout: every arriving byte restarts the timer
                available = now
                deadline = Date().addingTimeInterval(timeout)
            }
            if Date() > deadline { throw LoggerError(.timeout, detail: "\(source): no answer") }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func readUntil(_ terminator: [UInt8], maxLength: Int, timeout: TimeInterval) async throws -> [UInt8] {
        var result: [UInt8] = []
        while result.count < maxLength {
            result += try await read(count: 1, timeout: timeout)
            if result.count >= terminator.count, Array(result.suffix(terminator.count)) == terminator {
                return Array(result.dropLast(terminator.count))
            }
        }
        throw LoggerError(.protocolError, detail: "\(source): no terminator within \(maxLength) bytes")
    }

    func discardInput() async {
        handle.buffer.removeAll()
    }

    func setBaudRate(_ rate: Int) async throws {}
}

/// Finds and opens USB HID loggers by vendor and product ID (i-GotU GT-100/120/200/200e/600).
public struct IOKitHIDConnectionFactory: HIDConnectionFactory {
    public init() {}

    public func resourceKey(for entry: DeviceEntry) -> String {
        guard case .hid(let vendor, let products) = entry.connection else { return "hid:\(entry.id)" }
        return String(format: "hid:%04x:%04x", vendor, products.first ?? 0)
    }

    public func open(_ entry: DeviceEntry, diagnostics: any DiagnosticSink) async throws
        -> (any DeviceConnection, @Sendable () async -> Void) {
        guard case .hid(let vendor, let products) = entry.connection else {
            throw LoggerError(.deviceNotFound, detail: "\(entry.name) is not a USB HID device")
        }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching = products.map { [kIOHIDVendorIDKey: vendor, kIOHIDProductIDKey: $0] as CFDictionary }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let device = devices.first else {
            throw LoggerError(.deviceNotFound, detail: String(format: "No USB device %04x:%@ found", vendor,
                                                              products.map { String(format: "%04x", $0) }.joined(separator: "/")))
        }
        let handle = try HIDDeviceHandle(device: device)
        let source = resourceKey(for: entry)
        diagnostics.record(.event(source: source, name: DiagnosticEventName.open, detail: nil))
        let connection = HIDDeviceConnection(handle: handle, source: source, diagnostics: diagnostics)
        return (connection, {
            handle.close()
            diagnostics.record(.event(source: source, name: DiagnosticEventName.close, detail: nil))
        })
    }
}
