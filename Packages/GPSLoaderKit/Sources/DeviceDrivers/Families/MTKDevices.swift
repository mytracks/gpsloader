import GPSLoggerKitGPL

/// MTK based loggers (drivers `mtk` and `m241` in docs/legacy-device-catalog.md, change mtk-device-port).
enum MTKDevices {
    static func entry(_ id: String, _ name: String, model: MTKDevice.Model = .mtk) -> DeviceEntry {
        let device = MTKDevice(model: model)
        return DeviceEntry(id: "\(model == .mtk ? "mtk" : "m241").\(id)", name: name,
                           driverID: model == .mtk ? "mtk" : "m241", connection: .serial(baudRate: device.baudRate)) {
            device
        }
    }

    static let entries: [DeviceEntry] = [
        entry("blumax-gps-4044", "Blumax GPS-4044"),
        entry("iblue-747", "iBlue 747"),
        entry("itrek-z1", "iTrek Z1"),
        entry("networx-igeo", "Networx iGeo"),
        entry("photomate-887", "Photomate 887"),
        entry("qstarz-bt-100", "QStarz BT-100"),
        entry("qstarz-bt-q1000", "Qstarz BT-Q1000"),
        entry("qstarz-bt-q1300", "Qstarz BT-Q1300"),
        entry("transystem-860e", "Transystem 860E"),
        entry("holux-gpsport-245", "Holux GPSport 245", model: .holux),
        entry("holux-m-241", "Holux M-241", model: .holux),
    ]
}
