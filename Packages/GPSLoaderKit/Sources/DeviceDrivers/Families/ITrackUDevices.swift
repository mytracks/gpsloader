import GPSLoggerKitGPL

/// XAiOX iTrackU (driver `itracku`, "XAiOX iTrackU - gpsbabel" in docs/legacy-device-catalog.md, change itracku-port).
/// Over Bluetooth the device appears as `/dev/cu.*` after pairing.
enum ITrackUDevices {
    static let entries: [DeviceEntry] = [
        DeviceEntry(id: "itracku.xaiox-itracku", name: "XAiOX iTrackU", driverID: "itracku",
                    connection: .serial(baudRate: ITrackUDevice.baudRate)) { ITrackUDevice() },
    ]
}
