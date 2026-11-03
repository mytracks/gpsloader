import Foundation
import Testing
@testable import SerialTransport

@Suite("SerialPortCatalog")
struct SerialPortCatalogTests {
    @Test func listsCalloutDevicesOnly() {
        let ports = SerialPortCatalog.currentPorts()
        for port in ports {
            #expect(port.path.hasPrefix("/dev/cu."), "unexpected path \(port.path)")
            #expect(!port.name.hasPrefix("/dev/"))
        }
        #expect(ports.map(\.path) == ports.map(\.path).sorted())
    }

    @Test func portNameStripsPrefix() {
        let info = SerialPortInfo(path: "/dev/cu.SLAB_USBtoUART", usbVendorID: 0x10C4, usbProductID: 0xEA60)
        #expect(info.name == "SLAB_USBtoUART")
        #expect(info.isUSB)
        #expect(!SerialPortInfo(path: "/dev/cu.GNS2000").isUSB)
    }

    @Test func changeStreamStartsAndStopsCleanly() async throws {
        let stream = SerialPortCatalog.changes()
        let consumer = Task {
            for await _ in stream {}
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        consumer.cancel()
        _ = await consumer.value
    }
}
