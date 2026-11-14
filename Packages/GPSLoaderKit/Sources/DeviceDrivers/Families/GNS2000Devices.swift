import GPSLoggerKit

/// GNS 2000 / GNS 2000 plus over Bluetooth RFCOMM (driver `*GNS2000` in docs/legacy-device-catalog.md,
/// change gns2000-driver).
enum GNS2000Devices {
    static let entries: [DeviceEntry] = [
        DeviceEntry(id: "gns2000.gns-2000", name: "GNS 2000", driverID: "gns2000",
                    connection: .bluetooth(deviceNames: GNS2000Device.deviceNames, serviceName: GNS2000Device.serviceName),
                    hints: [DeviceHint(.always, .pairInSystemSettings)]) {
            GNS2000Device()
        },
    ]
}
