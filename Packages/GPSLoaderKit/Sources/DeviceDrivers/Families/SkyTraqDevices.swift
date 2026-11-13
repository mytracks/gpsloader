import GPSLoggerKitGPL

/// SkyTraq Venus loggers (driver `skytraq` in docs/legacy-device-catalog.md, change skytraq-device-port).
/// Baud rates follow the `additionalarguments` of the old catalog (`initbaud`, `baud`).
enum SkyTraqDevices {
    static func entry(_ id: String, _ name: String, initial: Int? = nil, download: Int = 230_400) -> DeviceEntry {
        DeviceEntry(id: "skytraq.\(id)", name: name, driverID: "skytraq", connection: .serial(baudRate: initial ?? 9600)) {
            SkyTraqDevice(initialBaudRate: initial, downloadBaudRate: download)
        }
    }

    static let entries: [DeviceEntry] = [
        entry("canmore-gt-730fl", "Canmore GT-730FL"),
        entry("canmore-gt-740fl", "Canmore GT-740FL"),
        entry("canmore-gt-750f", "Canmore GT-750F", initial: 38400, download: 38400),
        entry("conrad-gt-730", "Conrad GPS-Datenlogger GT-730", initial: 38400, download: 38400),
        entry("conrad-gt-750", "Conrad GPS-Datenlogger GT-750", initial: 38400, download: 38400),
        entry("doerr-photo-logger", "Dörr GPS Photo Logger", initial: 38400, download: 38400),
        entry("gisteq-dpl900", "Gisteq PhotoTrackr mini (DPL900)", initial: 38400, download: 38400),
        entry("navin-minihomer", "Navin MiniHomer", initial: 38400),
        entry("venus", "SkyTraq Venus"),
        entry("travel-honey", "Travel Honey"),
        entry("ventus-g730", "Ventus GPS Route Logger G730", initial: 38400, download: 38400),
    ]
}
