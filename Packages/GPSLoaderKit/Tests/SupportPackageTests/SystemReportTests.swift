import Foundation
import Testing
@testable import SerialTransport
@testable import SupportPackage

@Suite("Support package – parts")
struct SystemReportTests {
    @Test func systemText() {
        let report = SystemReport(appVersion: "1.0", build: "42", osVersion: "Version 27.0 (Build 27A100)", model: "Mac16,10",
                                  architecture: "arm64", isTranslated: false, languages: ["de-DE", "en"], timeZone: "Europe/Berlin")
        #expect(report.text.contains("gpsloader 1.0 (42)"))
        #expect(report.text.contains("Mac model: Mac16,10"))
        #expect(report.text.contains("Languages: de-DE, en"))
        #expect(!SystemReport.current(appVersion: "1", build: "1").model.isEmpty)
    }

    /// Scenario "Keine Seriennummern".
    @Test func usbDevicesWithoutSerialNumbers() {
        let properties: [String: Any] = [
            "idVendor": NSNumber(value: 0x10C4), "idProduct": NSNumber(value: 0xEA60),
            "USB Vendor Name": "Silicon Labs", "USB Product Name": "CP2102 USB to UART Bridge Controller",
            "USB Serial Number": "0001ABCD", "kUSBSerialNumberString": "0001ABCD", "locationID": NSNumber(value: 0x0110_0000),
        ]
        let device = USBDeviceCatalog.info(from: properties)
        #expect(device == USBDeviceInfo(vendorID: 0x10C4, productID: 0xEA60, vendorName: "Silicon Labs",
                                        productName: "CP2102 USB to UART Bridge Controller", locationID: 0x0110_0000))
        let text = SupportText.portsAndUSB(
            ports: [SerialPortInfo(path: "/dev/cu.SLAB_USBtoUART", usbVendorID: 0x10C4, usbProductID: 0xEA60,
                                   usbProductName: "CP2102 USB to UART Bridge Controller", usbVendorName: "Silicon Labs")],
            usb: [device].compactMap { $0 })
        #expect(text.contains("/dev/cu.SLAB_USBtoUART  USB 0x10C4:0xEA60  Silicon Labs / CP2102"))
        #expect(text.contains("0x10C4:0xEA60  Silicon Labs / CP2102 USB to UART Bridge Controller  location 0x01100000"))
        #expect(!text.contains("0001ABCD"))
        #expect(USBDeviceCatalog.info(from: ["USB Product Name": "Hub"]) == nil)
    }

    @Test func settingsAndCrashReports() throws {
        let data = try #require(SupportText.settings(["MainWindowSection": "device", "DeviceSelection": ["device": "mtk.holux-m-241"]]))
        #expect(String(decoding: data, as: UTF8.self).contains("mtk.holux-m-241"))
        #expect(SupportText.settings([:]) == nil)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("reports-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["gpsloader-2026-11-14-101010.ips", "Safari-2026-11-14-101010.ips", "gpsloader.txt"] {
            try Data("x".utf8).write(to: directory.appendingPathComponent(name))
        }
        #expect(CrashReports.find(in: [directory, directory.appendingPathComponent("Retired")]).map(\.lastPathComponent)
            == ["gpsloader-2026-11-14-101010.ips"])
    }
}
