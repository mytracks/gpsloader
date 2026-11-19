import Foundation
import GPSLoggerKit
import GPSLoggerKitGPL
import LoggerCore

/// How a device is connected.
public enum DeviceConnectionKind: Sendable, Equatable {
    /// A serial port (`/dev/cu.*`, USB-serial or Bluetooth) opened with this baud rate.
    case serial(baudRate: Int)
    /// A USB HID device found by vendor and product ID; no port selection.
    case hid(vendorID: Int, productIDs: [Int])
    /// A paired Bluetooth device found by name, connected over the RFCOMM channel of an SDP service;
    /// no port selection (change gns2000-driver).
    case bluetooth(deviceNames: [String], serviceName: String)
}

/// A note shown for a device (spec `device-mode`, "Device hints"); the app supplies the text.
public struct DeviceHint: Sendable, Equatable {
    public enum Condition: Sendable, Equatable {
        case always
        /// Only while a Bluetooth port is selected; also added to the message of a timeout.
        case bluetoothPort
    }

    public enum Message: Sendable, Equatable {
        /// Reading over Bluetooth is not reliable; connect the logger via USB (Holux M-241 on macOS 27).
        case useUSBInsteadOfBluetooth
        /// Pair the device in System Settings > Bluetooth first (GNS 2000).
        case pairInSystemSettings
        /// Connect the logger directly via USB; there is no port to choose (i-GotU over USB HID).
        case connectDirectlyViaUSB
    }

    public var condition: Condition
    public var message: Message

    public init(_ condition: Condition, _ message: Message) {
        self.condition = condition
        self.message = message
    }
}

/// One selectable device (spec `device-mode`, "Device catalog").
public struct DeviceEntry: Sendable, Identifiable {
    /// Stable identifier, e.g. "mtk.qstarz-bt-q1000"; stored as the user's selection.
    public var id: String
    public var name: String
    /// Driver family, e.g. "mtk"; used for diagnostics.
    public var driverID: String
    public var connection: DeviceConnectionKind
    /// Notes for the user (spec `device-mode`, "Device hints").
    public var hints: [DeviceHint]
    /// Creates the protocol for this device.
    public var makeProtocol: @Sendable () -> any DeviceProtocol

    public init(id: String, name: String, driverID: String, connection: DeviceConnectionKind, hints: [DeviceHint] = [],
                makeProtocol: @escaping @Sendable () -> any DeviceProtocol) {
        self.id = id
        self.name = name
        self.driverID = driverID
        self.connection = connection
        self.hints = hints
        self.makeProtocol = makeProtocol
    }

    public var eraseSupport: EraseSupport {
        switch makeProtocol().eraseSupport {
        case .unsupported: .unsupported
        case .supported: .supported
        case .experimental: .experimental
        }
    }

    public var needsPort: Bool {
        if case .serial = connection { return true }
        return false
    }
}

/// Opens a connection for HID devices; provided by the HID transport (i-GotU).
public protocol HIDConnectionFactory: Sendable {
    /// The resource key used to reserve the device, e.g. "hid:0df7:0900".
    func resourceKey(for entry: DeviceEntry) -> String
    /// Finds and opens the device; the returned closure closes it.
    func open(_ entry: DeviceEntry, diagnostics: any DiagnosticSink) async throws -> (any DeviceConnection, @Sendable () async -> Void)
}

/// Creates the transport for Bluetooth RFCOMM devices; provided by the Bluetooth transport (GNS 2000).
public protocol BluetoothTransportFactory: Sendable {
    /// The resource key used to reserve the device, e.g. "bluetooth:GNS 2000".
    func resourceKey(for entry: DeviceEntry) -> String
    /// A transport for the device; it connects in `open()`.
    func makeTransport(for entry: DeviceEntry) -> any ByteTransport
}

/// The devices of all available drivers, sorted by name.
public enum DeviceCatalog {
    public static var entries: [DeviceEntry] {
        DeviceCatalogContent.all.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func entry(withID id: String) -> DeviceEntry? {
        entries.first { $0.id == id }
    }
}

/// The catalog content; each driver family adds its entries here (changes skytraq-device-port etc.).
enum DeviceCatalogContent {
    static var all: [DeviceEntry] {
        SkyTraqDevices.entries + MTKDevices.entries + WintecDevices.entries + NavilinkDevices.entries
            + MagellanDevices.entries + ITrackUDevices.entries + IGotUDevices.entries + GNS2000Devices.entries
    }
}
