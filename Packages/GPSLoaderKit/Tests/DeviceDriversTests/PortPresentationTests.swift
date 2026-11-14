import Foundation
import Testing
import GPSLoggerKit
import SerialTransport
@testable import DeviceDrivers

private let m241 = DeviceCatalog.entry(withID: "m241.holux-m-241") ?? DeviceCatalog.entries[0]
private let usbPort = SerialPortInfo(path: "/dev/cu.usbserial-1410", usbVendorID: 0x067B, usbProductID: 0x2303,
                                     usbProductName: "USB-Serial Controller", usbLocationID: 0x0114_0000)
private let holuxBluetooth = SerialPortInfo(path: "/dev/cu.HOLUX_M-241-SPPSlave", isBluetooth: true)
private let otherBluetooth = SerialPortInfo(path: "/dev/cu.Qstarz-BT", isBluetooth: true)
private let incoming = SerialPortInfo(path: "/dev/cu.Bluetooth-Incoming-Port", isBluetooth: true)
private let console = SerialPortInfo(path: "/dev/cu.debug-console")

@Suite("Port presentation")
struct PortPresentationTests {
    /// Scenario "Passender Bluetooth-Anschluss".
    @Test func fittingBluetoothPortComesFirst() {
        #expect(m241.id == "m241.holux-m-241")
        let list = PortPresentation.list(ports: [incoming, otherBluetooth, usbPort, holuxBluetooth, console], for: m241)
        #expect(list.map(\.port.path) == [holuxBluetooth.path, usbPort.path, otherBluetooth.path])
        #expect(list.map(\.matchesDevice) == [true, false, false])
        #expect(list[0].label == .bluetooth(name: "HOLUX_M-241-SPPSlave"))
        #expect(list[1].label == .usb(product: "USB-Serial Controller", chip: "Prolific PL2303"))
        #expect(DeviceSelection.port(preferring: nil, in: [usbPort, holuxBluetooth], for: m241) == holuxBluetooth.path)
        var selection = DeviceSelection(entryID: "mtk.qstarz-bt-q1000", portPath: usbPort.path)
        selection.selectDevice(m241.id, entries: DeviceCatalog.entries, ports: [usbPort, holuxBluetooth])
        #expect(selection.portPath == holuxBluetooth.path)
        selection.selectDevice("mtk.qstarz-bt-q1000", entries: DeviceCatalog.entries, ports: [usbPort, holuxBluetooth])
        #expect(selection.portPath == holuxBluetooth.path)  // nothing fits: the port is kept
    }

    /// Scenario "Systemanschlüsse": the list is empty and the "no port" hint appears.
    @Test func systemPortsAreHidden() {
        #expect(PortPresentation.list(ports: [incoming, console], for: m241).isEmpty)
        let restored = DeviceSelection.restore(DeviceSelection(entryID: m241.id, portPath: incoming.path),
                                               entries: DeviceCatalog.entries, ports: [incoming, console])
        #expect(restored.portPath == nil)
        #expect(restored.hints(entries: DeviceCatalog.entries, ports: [incoming, console], usbDevices: []) == [.noPort])
    }

    @Test func nameMatching() throws {
        let q1000 = try #require(DeviceCatalog.entry(withID: "mtk.qstarz-bt-q1000"))
        #expect(PortPresentation.matches(SerialPortInfo(path: "/dev/cu.BT-Q1000X-GPS"), q1000))
        #expect(!PortPresentation.matches(SerialPortInfo(path: "/dev/cu.BT-Q1300"), q1000))
        let port = SerialPortInfo(path: "/dev/cu.SLAB_USBtoUART", usbVendorID: 0x10C4, usbProductID: 0xEA60)
        #expect(PortPresentation.label(for: port) == .usb(product: nil, chip: "Silicon Labs CP210x"))
        #expect(PortPresentation.label(for: SerialPortInfo(path: "/dev/ttys012")) == .other(name: "/dev/ttys012"))
    }
}

@Suite("Device hints")
struct DeviceHintTests {
    /// Scenario "M-241 über Bluetooth" (also for the timeout message, scenario "Fehlschlag über Bluetooth").
    @Test func m241OverBluetooth() {
        let ports = [usbPort, holuxBluetooth]
        let overBluetooth = DeviceSelection(entryID: m241.id, portPath: holuxBluetooth.path)
        #expect(overBluetooth.hints(entries: DeviceCatalog.entries, ports: ports, usbDevices: []) == [.device(.useUSBInsteadOfBluetooth)])
        #expect(overBluetooth.failureHints(entries: DeviceCatalog.entries, ports: ports) == [.useUSBInsteadOfBluetooth])
        let overUSB = DeviceSelection(entryID: m241.id, portPath: usbPort.path)
        #expect(overUSB.hints(entries: DeviceCatalog.entries, ports: ports, usbDevices: []).isEmpty)
        #expect(overUSB.failureHints(entries: DeviceCatalog.entries, ports: ports).isEmpty)
    }

    /// Scenarios "Treiber fehlt" and "Treiber vorhanden".
    @Test func missingDriver() throws {
        let prolific = USBDeviceInfo(vendorID: 0x067B, productID: 0x2303, locationID: 0x0114_0000)
        let hub = USBDeviceInfo(vendorID: 0x047D, productID: 0x8080, locationID: 0x0110_0000)
        let selection = DeviceSelection(entryID: m241.id, portPath: nil)
        let chip = try #require(USBSerialChip.chip(vendorID: 0x067B))
        #expect(selection.hints(entries: DeviceCatalog.entries, ports: [], usbDevices: [hub, prolific]) == [.noPort, .driverMissing(chip)])
        #expect(chip.driverPage.absoluteString == "https://apps.apple.com/app/pl2303-serial/id1624835354")
        let withPort = DeviceSelection(entryID: m241.id, portPath: usbPort.path)
        #expect(withPort.hints(entries: DeviceCatalog.entries, ports: [usbPort], usbDevices: [hub, prolific]).isEmpty)
        // Devices without a serial port (i-GotU over HID, GNS 2000) get no driver hint.
        let igotu = DeviceSelection(entryID: "igotu.gt-120", portPath: nil)
        #expect(igotu.hints(entries: DeviceCatalog.entries, ports: [], usbDevices: [prolific]) == [.device(.connectDirectlyViaUSB)])
    }

    @Test func chipsAndPages() {
        #expect(USBSerialChip.all.map(\.vendorID) == [0x10C4, 0x067B, 0x0403, 0x1A86])
        #expect(USBSerialChip.all.allSatisfy { $0.driverPage.scheme == "https" })
        #expect(USBSerialChip.chip(vendorID: 0x1234) == nil)
    }
}
