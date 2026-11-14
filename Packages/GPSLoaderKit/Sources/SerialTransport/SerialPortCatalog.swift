import Foundation
import IOKit
import IOKit.serial
import LoggerCore

/// What a serial port belongs to (spec `serial-transport`, "Art des Anschlusses").
public enum SerialPortKind: String, Sendable, Hashable {
    /// A USB device, e.g. a USB-serial adapter or a logger with a built-in chip.
    case usb
    /// A paired Bluetooth device (serial port profile).
    case bluetooth
    /// A port of macOS itself (`Bluetooth-Incoming-Port`, debug consoles); never a logger.
    case system
    /// Anything else, e.g. a pseudo terminal.
    case other
}

/// A serial port present on the system (spec `serial-transport`, "Ports ermitteln").
public struct SerialPortInfo: Sendable, Hashable, Identifiable {
    /// Callout device path, e.g. `/dev/cu.SLAB_USBtoUART`.
    public var path: String
    /// USB vendor ID of the adapter, if the port belongs to a USB device.
    public var usbVendorID: Int?
    /// USB product ID of the adapter, if the port belongs to a USB device.
    public var usbProductID: Int?
    public var usbProductName: String?
    public var usbVendorName: String?
    /// Physical USB location; matches `USBDeviceInfo.locationID` of the device the port belongs to.
    public var usbLocationID: Int?
    public var kind: SerialPortKind

    public var id: String { path }

    /// Port name without the `/dev/cu.` prefix, e.g. `SLAB_USBtoUART`.
    public var name: String {
        path.hasPrefix("/dev/cu.") ? String(path.dropFirst("/dev/cu.".count)) : path
    }

    public var isUSB: Bool { usbVendorID != nil }

    public init(path: String, usbVendorID: Int? = nil, usbProductID: Int? = nil,
                usbProductName: String? = nil, usbVendorName: String? = nil, usbLocationID: Int? = nil,
                isBluetooth: Bool = false) {
        self.path = path
        self.usbVendorID = usbVendorID
        self.usbProductID = usbProductID
        self.usbProductName = usbProductName
        self.usbVendorName = usbVendorName
        self.usbLocationID = usbLocationID
        kind = .other
        kind = Self.kind(name: name, isUSB: usbVendorID != nil, isBluetooth: isBluetooth)
    }

    /// Design D1: system ports first (the incoming port also hangs below a Bluetooth device), then Bluetooth
    /// (a parent has `BTAddress`), then USB (a parent has `idVendor`).
    static func kind(name: String, isUSB: Bool, isBluetooth: Bool) -> SerialPortKind {
        if name == "Bluetooth-Incoming-Port" { return .system }
        if isBluetooth { return .bluetooth }
        if isUSB { return .usb }
        if name.lowercased().contains("debug") { return .system }
        return .other
    }
}

/// A port appeared or disappeared (spec `serial-transport`, "Port-Änderungen erkennen").
public enum SerialPortChange: Sendable, Equatable {
    case added(SerialPortInfo)
    case removed(path: String)
}

/// Lists serial ports via IOKit and reports changes.
public enum SerialPortCatalog {
    /// All serial ports that currently exist, sorted by path.
    public static func currentPorts() -> [SerialPortInfo] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchingDictionary(), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        return drain(iterator).sorted { $0.path < $1.path }
    }

    /// A stream of added and removed ports. Ports present when the stream starts are *not* reported;
    /// combine with `currentPorts()`. The IOKit notifications are removed when the stream terminates.
    public static func changes() -> AsyncStream<SerialPortChange> {
        AsyncStream { continuation in
            let observer = NotificationObserver(continuation: continuation)
            guard observer.start() else {
                continuation.finish()
                return
            }
            continuation.onTermination = { _ in observer.stop() }
        }
    }

    // MARK: - Internals

    static func matchingDictionary() -> CFMutableDictionary {
        let dictionary = IOServiceMatching(kIOSerialBSDServiceValue) as NSMutableDictionary
        dictionary[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes
        return dictionary as CFMutableDictionary
    }

    /// Reads all services from an iterator (this also re-arms notification iterators).
    static func drain(_ iterator: io_iterator_t) -> [SerialPortInfo] {
        var ports: [SerialPortInfo] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            if let info = portInfo(for: service) {
                ports.append(info)
            }
            IOObjectRelease(service)
        }
        return ports
    }

    static func portInfo(for service: io_object_t) -> SerialPortInfo? {
        guard let path = property(service, key: kIOCalloutDeviceKey, searchParents: false) as? String else {
            return nil
        }
        return SerialPortInfo(
            path: path,
            usbVendorID: (property(service, key: "idVendor", searchParents: true) as? NSNumber)?.intValue,
            usbProductID: (property(service, key: "idProduct", searchParents: true) as? NSNumber)?.intValue,
            usbProductName: property(service, key: "USB Product Name", searchParents: true) as? String,
            usbVendorName: property(service, key: "USB Vendor Name", searchParents: true) as? String,
            usbLocationID: (property(service, key: "locationID", searchParents: true) as? NSNumber)?.intValue,
            isBluetooth: property(service, key: "BTAddress", searchParents: true) != nil
        )
    }

    private static func property(_ service: io_object_t, key: String, searchParents: Bool) -> Any? {
        if searchParents {
            let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
            return IORegistryEntrySearchCFProperty(service, kIOServicePlane, key as CFString, kCFAllocatorDefault, options)
        }
        return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}

/// Owns the IOKit notification port and iterators for `SerialPortCatalog.changes()`.
/// All IOKit callbacks run on `queue`; the mutable state is only touched there or under the lock.
private final class NotificationObserver: @unchecked Sendable {
    private let continuation: AsyncStream<SerialPortChange>.Continuation
    private let queue = DispatchQueue(label: "gpsloader.serial.catalog")
    private let state = Locked<State>(State())

    private struct State: @unchecked Sendable {
        var notificationPort: IONotificationPortRef?
        var addedIterator: io_iterator_t = 0
        var removedIterator: io_iterator_t = 0
    }

    init(continuation: AsyncStream<SerialPortChange>.Continuation) {
        self.continuation = continuation
    }

    func start() -> Bool {
        guard let notificationPort = IONotificationPortCreate(kIOMainPortDefault) else { return false }
        IONotificationPortSetDispatchQueue(notificationPort, queue)
        let refcon = Unmanaged.passRetained(self).toOpaque()

        var added: io_iterator_t = 0
        var removed: io_iterator_t = 0
        let addedResult = IOServiceAddMatchingNotification(
            notificationPort, kIOFirstMatchNotification, SerialPortCatalog.matchingDictionary(),
            { refcon, iterator in
                guard let refcon else { return }
                let observer = Unmanaged<NotificationObserver>.fromOpaque(refcon).takeUnretainedValue()
                for port in SerialPortCatalog.drain(iterator) {
                    observer.continuation.yield(.added(port))
                }
            },
            refcon, &added)
        let removedResult = IOServiceAddMatchingNotification(
            notificationPort, kIOTerminatedNotification, SerialPortCatalog.matchingDictionary(),
            { refcon, iterator in
                guard let refcon else { return }
                let observer = Unmanaged<NotificationObserver>.fromOpaque(refcon).takeUnretainedValue()
                for port in SerialPortCatalog.drain(iterator) {
                    observer.continuation.yield(.removed(path: port.path))
                }
            },
            refcon, &removed)

        guard addedResult == KERN_SUCCESS, removedResult == KERN_SUCCESS else {
            if added != 0 { IOObjectRelease(added) }
            if removed != 0 { IOObjectRelease(removed) }
            IONotificationPortDestroy(notificationPort)
            Unmanaged<NotificationObserver>.fromOpaque(refcon).release()
            return false
        }

        // Arm the notifications. Existing ports are skipped on purpose (see `changes()`).
        _ = SerialPortCatalog.drain(added)
        _ = SerialPortCatalog.drain(removed)

        state.withLock {
            $0.notificationPort = notificationPort
            $0.addedIterator = added
            $0.removedIterator = removed
        }
        return true
    }

    func stop() {
        let current = state.withLock { state -> State in
            let copy = state
            state = State()
            return copy
        }
        guard current.notificationPort != nil else { return }
        queue.async {
            IOObjectRelease(current.addedIterator)
            IOObjectRelease(current.removedIterator)
            if let notificationPort = current.notificationPort {
                IONotificationPortDestroy(notificationPort)
            }
            Unmanaged<NotificationObserver>.passUnretained(self).release()
        }
    }
}
