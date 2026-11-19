import Foundation
import SerialTransport

/// Manufacturers of USB-serial chips whose missing driver gpsloader can point out
/// (spec `device-mode`, "Missing driver"; design D2 of change device-ports-and-hints).
public struct USBSerialChip: Sendable, Hashable {
    public var vendorID: Int
    /// Manufacturer and chip family, e.g. "Silicon Labs CP210x".
    public var name: String
    /// The manufacturer's driver page.
    public var driverPage: URL

    public static let all: [USBSerialChip] = [
        USBSerialChip(vendorID: 0x10C4, name: "Silicon Labs CP210x",
                      driverPage: URL(string: "https://www.silabs.com/software-and-tools/usb-to-uart-bridge-vcp-drivers")!),
        USBSerialChip(vendorID: 0x067B, name: "Prolific PL2303",
                      driverPage: URL(string: "https://apps.apple.com/app/pl2303-serial/id1624835354")!),
        USBSerialChip(vendorID: 0x0403, name: "FTDI",
                      driverPage: URL(string: "https://ftdichip.com/drivers/vcp-drivers/")!),
        USBSerialChip(vendorID: 0x1A86, name: "WCH CH34x",
                      driverPage: URL(string: "https://github.com/WCHSoftGroup/ch34xser_macos")!),
    ]

    public static func chip(vendorID: Int?) -> USBSerialChip? {
        all.first { $0.vendorID == vendorID }
    }
}

/// How a port is shown in the port selection; the app turns it into a localized title.
public enum PortLabel: Sendable, Equatable {
    /// A USB port with the product name of the device and/or the chip manufacturer.
    case usb(product: String?, chip: String?)
    /// A Bluetooth port with the name of the port (the paired device).
    case bluetooth(name: String)
    case other(name: String)
}

/// One visible entry of the port selection.
public struct PresentedPort: Sendable, Equatable {
    public var port: SerialPortInfo
    public var label: PortLabel
    /// The port's name fits the selected device (design D3).
    public var matchesDevice: Bool
}

/// Visible ports in the order of the selection (spec `device-mode`, "Choose the port"; design D3):
/// fitting the device, then USB, then Bluetooth, then the rest; system ports are left out.
public enum PortPresentation {
    public static func list(ports: [SerialPortInfo], for entry: DeviceEntry?) -> [PresentedPort] {
        let visible = ports.filter { $0.kind != .system }.map { port in
            PresentedPort(port: port, label: label(for: port), matchesDevice: entry.map { matches(port, $0) } ?? false)
        }
        func rank(_ item: PresentedPort) -> Int {
            if item.matchesDevice { return 0 }
            switch item.port.kind {
            case .usb: return 1
            case .bluetooth: return 2
            case .other, .system: return 3
            }
        }
        return visible.sorted { (rank($0), $0.port.path) < (rank($1), $1.port.path) }
    }

    static func label(for port: SerialPortInfo) -> PortLabel {
        switch port.kind {
        case .usb:
            let product = port.usbProductName?.trimmingCharacters(in: .whitespaces)
            return .usb(product: product?.isEmpty == false ? product : nil, chip: USBSerialChip.chip(vendorID: port.usbVendorID)?.name)
        case .bluetooth:
            return .bluetooth(name: port.name)
        case .other, .system:
            return .other(name: port.name)
        }
    }

    /// The port name contains the device name or the device name without its first word (the brand),
    /// both reduced to lower-case letters and digits; the latter needs at least 4 characters.
    static func matches(_ port: SerialPortInfo, _ entry: DeviceEntry) -> Bool {
        func reduced<S: StringProtocol>(_ text: S) -> String { String(text.lowercased().filter { $0.isLetter || $0.isNumber }) }
        let name = reduced(port.name + " " + (port.usbProductName ?? ""))
        let words = entry.name.split(separator: " ")
        let full = reduced(entry.name)
        let model = reduced(words.dropFirst().joined(separator: " "))
        return (!full.isEmpty && name.contains(full)) || (model.count >= 4 && name.contains(model))
    }
}
