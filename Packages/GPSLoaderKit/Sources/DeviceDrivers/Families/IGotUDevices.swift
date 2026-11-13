import GPSLoggerKitGPL

/// i-GotU loggers (docs/legacy-analysis.md, section 3.2; change igotu-driver): the GT-800 over a serial port,
/// the USB models over USB HID. Erasing is experimental.
enum IGotUDevices {
    static func serial(_ id: String, _ name: String) -> DeviceEntry {
        DeviceEntry(id: "igotu.\(id)", name: name, driverID: "igotu",
                    connection: .serial(baudRate: IGotUDevice.serialBaudRate)) { IGotUDevice(variant: .serial) }
    }

    static func usb(_ id: String, _ name: String) -> DeviceEntry {
        DeviceEntry(id: "igotu.\(id)", name: name, driverID: "igotu",
                    connection: .hid(vendorID: IGotUDevice.usbVendorID, productIDs: IGotUDevice.usbProductIDs)) {
            IGotUDevice(variant: .hid)
        }
    }

    static let entries: [DeviceEntry] = [
        usb("gt-100", "i-GotU GT-100"),
        usb("gt-120", "i-GotU GT-120"),
        usb("gt-200", "i-GotU GT-200"),
        usb("gt-200e", "i-GotU GT-200e"),
        usb("gt-600", "i-GotU GT-600"),
        serial("gt-800", "i-gotU GT-800"),
        serial("gt-800-pro", "i-gotU GT-800 Pro"),
    ]
}
