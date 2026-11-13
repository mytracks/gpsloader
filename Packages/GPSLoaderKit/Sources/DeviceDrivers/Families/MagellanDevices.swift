import GPSLoggerKitGPL

/// Magellan Meridian and SporTrak devices (driver `magellan`, USB serial, in docs/legacy-device-catalog.md,
/// change magellan-port).
enum MagellanDevices {
    static func entry(_ id: String, _ name: String) -> DeviceEntry {
        DeviceEntry(id: "magellan.\(id)", name: name, driverID: "magellan",
                    connection: .serial(baudRate: MagellanDevice.baudRate)) { MagellanDevice() }
    }

    static let entries: [DeviceEntry] = [
        entry("meridian", "Magellan Meridian"),
        entry("meridian-gold", "Magellan Meridian Gold"),
        entry("meridian-platinum", "Magellan Meridian Platinum"),
        entry("sportrak-map", "Magellan SporTrak Map"),
        entry("sportrak-map-color", "Magellan SporTrak Map Color"),
        entry("sportrak-map-pro", "Magellan SporTrak Map Pro"),
        entry("sportrak-map-topo", "Magellan SporTrak Map Topo"),
    ]
}
