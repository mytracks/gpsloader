import GPSLoggerKitGPL

/// Locosys NaviGPS devices in NAVILINK mode (driver `navilink` in docs/legacy-device-catalog.md,
/// change navilink-device-port).
enum NavilinkDevices {
    static func entry(_ id: String, _ name: String) -> DeviceEntry {
        DeviceEntry(id: "navilink.\(id)", name: name, driverID: "navilink",
                    connection: .serial(baudRate: NavilinkDevice.baudRate)) { NavilinkDevice() }
    }

    static let entries: [DeviceEntry] = [
        entry("locosys-bgt-31", "Locosys BGT-31"),
        entry("locosys-gt-11", "Locosys GT-11"),
        entry("locosys-gt-31", "Locosys GT-31"),
        entry("navigps", "NaviGPS"),
        entry("navigps-bt", "NaviGPS-BT"),
        entry("generic", "Navilink - generic"),
    ]
}
