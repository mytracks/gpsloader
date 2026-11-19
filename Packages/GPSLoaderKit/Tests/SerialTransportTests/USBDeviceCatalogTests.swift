import Foundation
import Testing
@testable import SerialTransport

@Suite("USBDeviceCatalog")
struct USBDeviceCatalogTests {
    /// Scenario "Adapter without driver": the device is listed although no port belongs to it.
    @Test func adapterWithoutPort() {
        let adapter = USBDeviceInfo(vendorID: 0x067B, productID: 0x2303, productName: "USB-Serial Controller", locationID: 0x0114_0000)
        let other = SerialPortInfo(path: "/dev/cu.SLAB_USBtoUART", usbVendorID: 0x10C4, usbProductID: 0xEA60, usbLocationID: 0x0120_0000)
        #expect(!adapter.hasPort(in: [other]))
        let own = SerialPortInfo(path: "/dev/cu.usbserial-1410", usbVendorID: 0x067B, usbProductID: 0x2303, usbLocationID: 0x0114_0000)
        #expect(adapter.hasPort(in: [other, own]))
        // Two adapters of the same kind: the location decides.
        let second = SerialPortInfo(path: "/dev/cu.usbserial-1420", usbVendorID: 0x067B, usbProductID: 0x2303, usbLocationID: 0x0115_0000)
        #expect(!adapter.hasPort(in: [second]))
        // Without locations, vendor and product ID decide.
        #expect(USBDeviceInfo(vendorID: 0x067B, productID: 0x2303).hasPort(in: [SerialPortInfo(path: "/dev/cu.x", usbVendorID: 0x067B, usbProductID: 0x2303)]))
    }

    @Test func listsDevicesAndStream() async throws {
        for device in USBDeviceCatalog.currentDevices() { #expect(device.vendorID >= 0) }
        let consumer = Task { for await _ in USBDeviceCatalog.changes() {} }
        try await Task.sleep(nanoseconds: 100_000_000)
        consumer.cancel()
        _ = await consumer.value
    }
}
