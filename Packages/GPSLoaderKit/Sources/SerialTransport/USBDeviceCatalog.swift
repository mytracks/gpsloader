import Foundation
import IOKit
import IOKit.usb
import LoggerCore

/// A connected USB device (spec `serial-transport`, "USB-Geräte ermitteln"). Serial numbers are never read.
public struct USBDeviceInfo: Sendable, Hashable {
    public var vendorID: Int
    public var productID: Int
    public var vendorName: String?
    public var productName: String?
    /// Physical location on the bus; identifies the device together with its serial port.
    public var locationID: Int?

    public init(vendorID: Int, productID: Int, vendorName: String? = nil, productName: String? = nil, locationID: Int? = nil) {
        self.vendorID = vendorID
        self.productID = productID
        self.vendorName = vendorName
        self.productName = productName
        self.locationID = locationID
    }
}

extension USBDeviceInfo {
    /// Whether one of `ports` belongs to this device: same USB location, or (without locations) the same
    /// vendor and product ID. Without a port, no driver has attached to the device (change device-ports-and-hints, D5).
    public func hasPort(in ports: [SerialPortInfo]) -> Bool {
        ports.contains { port in
            if let location = locationID, let portLocation = port.usbLocationID { return location == portLocation }
            return port.usbVendorID == vendorID && port.usbProductID == productID
        }
    }
}

/// Lists the connected USB devices via IOKit (class `IOUSBHostDevice`).
public enum USBDeviceCatalog {
    /// Signals each time a USB device is connected or disconnected. Devices present when the stream starts are
    /// not reported. A USB-serial adapter without driver creates no serial port, so this is the only way to notice it.
    public static func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let observer = USBNotificationObserver(continuation: continuation)
            guard observer.start() else {
                continuation.finish()
                return
            }
            continuation.onTermination = { _ in observer.stop() }
        }
    }

    public static func currentDevices() -> [USBDeviceInfo] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var devices: [USBDeviceInfo] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dictionary = properties?.takeRetainedValue() as? [String: Any],
                  let info = info(from: dictionary) else { continue }
            devices.append(info)
        }
        return devices.sorted { ($0.locationID ?? 0, $0.vendorID, $0.productID) < ($1.locationID ?? 0, $1.vendorID, $1.productID) }
    }

    /// The fields gpsloader uses; everything else (in particular `USB Serial Number`) is dropped.
    static func info(from properties: [String: Any]) -> USBDeviceInfo? {
        guard let vendor = (properties["idVendor"] as? NSNumber)?.intValue,
              let product = (properties["idProduct"] as? NSNumber)?.intValue else { return nil }
        return USBDeviceInfo(vendorID: vendor, productID: product,
                             vendorName: properties["USB Vendor Name"] as? String,
                             productName: properties["USB Product Name"] as? String,
                             locationID: (properties["locationID"] as? NSNumber)?.intValue)
    }
}

/// IOKit notifications for USB devices; the same pattern as the observer of `SerialPortCatalog.changes()`.
private final class USBNotificationObserver: @unchecked Sendable {
    private let continuation: AsyncStream<Void>.Continuation
    private let queue = DispatchQueue(label: "gpsloader.usb.catalog")
    private let state = Locked<State>(State())

    private struct State: @unchecked Sendable {
        var notificationPort: IONotificationPortRef?
        var iterators: [io_iterator_t] = []
    }

    init(continuation: AsyncStream<Void>.Continuation) {
        self.continuation = continuation
    }

    /// Empties an iterator (this also re-arms it) and releases the services.
    static func drain(_ iterator: io_iterator_t) -> Int {
        var count = 0
        while case let service = IOIteratorNext(iterator), service != 0 {
            IOObjectRelease(service)
            count += 1
        }
        return count
    }

    func start() -> Bool {
        guard let notificationPort = IONotificationPortCreate(kIOMainPortDefault) else { return false }
        IONotificationPortSetDispatchQueue(notificationPort, queue)
        let refcon = Unmanaged.passRetained(self).toOpaque()
        var iterators: [io_iterator_t] = []
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(
                notificationPort, type, IOServiceMatching("IOUSBHostDevice"),
                { refcon, iterator in
                    guard let refcon else { return }
                    let observer = Unmanaged<USBNotificationObserver>.fromOpaque(refcon).takeUnretainedValue()
                    if USBNotificationObserver.drain(iterator) > 0 { observer.continuation.yield(()) }
                },
                refcon, &iterator)
            guard result == KERN_SUCCESS else {
                iterators.forEach { IOObjectRelease($0) }
                IONotificationPortDestroy(notificationPort)
                Unmanaged<USBNotificationObserver>.fromOpaque(refcon).release()
                return false
            }
            _ = Self.drain(iterator)  // arm; existing devices are skipped on purpose
            iterators.append(iterator)
        }
        state.withLock {
            $0.notificationPort = notificationPort
            $0.iterators = iterators
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
            current.iterators.forEach { IOObjectRelease($0) }
            if let notificationPort = current.notificationPort { IONotificationPortDestroy(notificationPort) }
            Unmanaged<USBNotificationObserver>.passUnretained(self).release()
        }
    }
}
