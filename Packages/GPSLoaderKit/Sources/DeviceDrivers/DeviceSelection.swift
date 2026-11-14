import Foundation
import LoggerCore
import SerialTransport

/// The selection in the device panel and what it allows (spec `device-mode`), independent of AppKit.
public struct DeviceSelection: Sendable, Equatable {
    public enum Hint: Sendable, Equatable {
        /// The selected device needs a serial port, but none is present.
        case noPort
        /// A note of the catalog entry whose condition applies.
        case device(DeviceHint.Message)
        /// A USB device with this chip is connected, but no port belongs to it: its driver is probably missing.
        case driverMissing(USBSerialChip)
    }

    public var entryID: String?
    public var portPath: String?

    public init(entryID: String? = nil, portPath: String? = nil) {
        self.entryID = entryID
        self.portPath = portPath
    }

    /// Restores a stored selection: the device if it still exists (else the first one), the port if it is
    /// still visible (else the first port of the presentation order). Scenario "Auswahl merken".
    public static func restore(_ stored: DeviceSelection, entries: [DeviceEntry], ports: [SerialPortInfo]) -> DeviceSelection {
        let entry = entries.first { $0.id == stored.entryID } ?? entries.first
        return DeviceSelection(entryID: entry?.id, portPath: port(preferring: stored.portPath, in: ports, for: entry))
    }

    /// Keeps the selected port when the port list changes, otherwise picks the first port in the order of
    /// `PortPresentation` (scenarios "Logger angesteckt", "Passender Bluetooth-Anschluss"). System ports are never chosen.
    public static func port(preferring path: String?, in ports: [SerialPortInfo], for entry: DeviceEntry? = nil) -> String? {
        let visible = PortPresentation.list(ports: ports, for: entry)
        if let path, visible.contains(where: { $0.port.path == path }) { return path }
        return visible.first?.port.path
    }

    /// Selects another device; a port that fits its name is preselected, otherwise the port is kept.
    public mutating func selectDevice(_ id: String, entries: [DeviceEntry], ports: [SerialPortInfo]) {
        entryID = id
        let entry = entry(in: entries)
        if let fitting = PortPresentation.list(ports: ports, for: entry).first(where: \.matchesDevice) {
            portPath = fitting.port.path
        } else {
            portPath = Self.port(preferring: portPath, in: ports, for: entry)
        }
    }

    public func entry(in entries: [DeviceEntry]) -> DeviceEntry? {
        entries.first { $0.id == entryID }
    }

    /// The hints for the current selection (spec `device-mode`, "Hinweise zum Gerät", "Fehlender Treiber").
    public func hints(entries: [DeviceEntry], ports: [SerialPortInfo], usbDevices: [USBDeviceInfo]) -> [Hint] {
        guard let entry = entry(in: entries) else { return [] }
        var hints: [Hint] = []
        if entry.needsPort, portPath == nil { hints.append(.noPort) }
        hints += applicableDeviceHints(entry, ports: ports).map { .device($0.message) }
        if entry.needsPort {
            var chips: [USBSerialChip] = []
            for device in usbDevices where !device.hasPort(in: ports) {
                if let chip = USBSerialChip.chip(vendorID: device.vendorID), !chips.contains(chip) { chips.append(chip) }
            }
            hints += chips.map { .driverMissing($0) }
        }
        return hints
    }

    /// The hints with the condition "Bluetooth port" that apply now; added to the message of a failed read.
    public func failureHints(entries: [DeviceEntry], ports: [SerialPortInfo]) -> [DeviceHint.Message] {
        guard let entry = entry(in: entries) else { return [] }
        return applicableDeviceHints(entry, ports: ports).filter { $0.condition == .bluetoothPort }.map(\.message)
    }

    private func applicableDeviceHints(_ entry: DeviceEntry, ports: [SerialPortInfo]) -> [DeviceHint] {
        let onBluetooth = entry.needsPort && ports.first { $0.path == portPath }?.kind == .bluetooth
        return entry.hints.filter { $0.condition == .always || onBluetooth }
    }

    /// Scenario "Kein Anschluss".
    public func canRead(entries: [DeviceEntry], isRunning: Bool) -> Bool {
        guard !isRunning, let entry = entry(in: entries) else { return false }
        return !entry.needsPort || portPath != nil
    }

    /// Scenario "Gerät ohne Löschfunktion".
    public func canErase(entries: [DeviceEntry], isRunning: Bool) -> Bool {
        canRead(entries: entries, isRunning: isRunning) && entry(in: entries)?.eraseSupport != .unsupported
    }

    /// Storage in user defaults ("DeviceSelection").
    public var stored: [String: String] {
        var result: [String: String] = [:]
        result["device"] = entryID
        result["port"] = portPath
        return result
    }

    public init(stored: [String: String]?) {
        self.init(entryID: stored?["device"], portPath: stored?["port"])
    }
}
