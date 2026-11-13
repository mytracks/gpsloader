import Foundation
import LoggerCore
import SerialTransport

/// The selection in the device panel and what it allows (spec `device-mode`), independent of AppKit.
public struct DeviceSelection: Sendable, Equatable {
    public enum Hint: Sendable, Equatable {
        /// The selected device needs a serial port, but none is present.
        case noPort
    }

    public var entryID: String?
    public var portPath: String?

    public init(entryID: String? = nil, portPath: String? = nil) {
        self.entryID = entryID
        self.portPath = portPath
    }

    /// Restores a stored selection: the device if it still exists (else the first one), the port if it is
    /// still present (else the first USB port, else the first port). Scenario "Auswahl merken".
    public static func restore(_ stored: DeviceSelection, entries: [DeviceEntry], ports: [SerialPortInfo]) -> DeviceSelection {
        let entry = entries.first { $0.id == stored.entryID } ?? entries.first
        return DeviceSelection(entryID: entry?.id, portPath: port(preferring: stored.portPath, in: ports))
    }

    /// Keeps the selected port when the port list changes, otherwise picks a replacement
    /// (scenario "Logger angesteckt").
    public static func port(preferring path: String?, in ports: [SerialPortInfo]) -> String? {
        if let path, ports.contains(where: { $0.path == path }) { return path }
        return (ports.first { $0.isUSB } ?? ports.first)?.path
    }

    public func entry(in entries: [DeviceEntry]) -> DeviceEntry? {
        entries.first { $0.id == entryID }
    }

    public func hint(entries: [DeviceEntry]) -> Hint? {
        guard let entry = entry(in: entries), entry.needsPort, portPath == nil else { return nil }
        return .noPort
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
