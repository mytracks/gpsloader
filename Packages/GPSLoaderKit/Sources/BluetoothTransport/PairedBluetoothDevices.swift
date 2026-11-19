import CoreBluetooth
import Foundation
import IOBluetooth

/// The paired Bluetooth devices for the support package (spec `support-package`, "Privacy in the support package").
@MainActor
public enum PairedBluetoothDevices {
    /// Whether gpsloader already has the Bluetooth permission. Reading `CBManager.authorization` never shows a dialog.
    public static var isAuthorized: Bool {
        CBManager.authorization == .allowedAlways
    }

    /// One line per paired device (name, address, connected); `nil` without the permission, so that no
    /// permission dialog appears. IOBluetooth is only called after this check.
    public static func listIfAuthorized() -> String? {
        guard isAuthorized else { return nil }
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        let lines = devices.map { device in
            "\(device.name ?? "?")  \(device.addressString ?? "?")\(device.isConnected() ? "  connected" : "")"
        }
        return (["Paired Bluetooth devices (\(devices.count)):"] + lines.map { "  " + $0 }).joined(separator: "\n") + "\n"
    }
}
