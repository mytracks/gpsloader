import GPSLoggerKitGPL

/// Wintec loggers (driver `wbt` in docs/legacy-device-catalog.md, change wintec-device-port).
/// One driver for all: the device type (WBT-200 at 9600 baud, WBT-201/WSG-1000 at 57600 baud) is detected.
enum WintecDevices {
    static func entry(_ id: String, _ name: String) -> DeviceEntry {
        DeviceEntry(id: "wbt.\(id)", name: name, driverID: "wbt", connection: .serial(baudRate: WintecDevice.wbt200Baud)) {
            WintecDevice()
        }
    }

    static let entries: [DeviceEntry] = [
        entry("g-rays-2", "G-Rays 2"),
        entry("wintec-wbt-100", "Wintec WBT-100"),
        entry("wintec-wbt-200", "Wintec WBT-200"),
        entry("wintec-wbt-201", "Wintec WBT-201"),
        entry("wintec-wsg-1000", "Wintec WSG-1000 (G-Tender)"),
    ]
}
