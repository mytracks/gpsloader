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

    /// Scenarios "Paired Bluetooth device" and "System port" (properties as observed on macOS 27).
    @Test func kindOfPort() {
        #expect(SerialPortInfo(path: "/dev/cu.HOLUX_M-241-SPPSlave", isBluetooth: true).kind == .bluetooth)
        #expect(SerialPortInfo(path: "/dev/cu.GNS2000", isBluetooth: true).kind == .bluetooth)
        #expect(SerialPortInfo(path: "/dev/cu.Bluetooth-Incoming-Port", isBluetooth: true).kind == .system)
        #expect(SerialPortInfo(path: "/dev/cu.debug-console").kind == .system)
        #expect(SerialPortInfo(path: "/dev/cu.wlan-debug").kind == .system)
        #expect(SerialPortInfo(path: "/dev/cu.usbserial-1410", usbVendorID: 0x067B, usbProductID: 0x2303,
                               usbLocationID: 0x0114_0000).kind == .usb)
        #expect(SerialPortInfo(path: "/dev/ttys012").kind == .other)
    }

    /// The ports of this Mac: every port has a kind, and the incoming port is a system port.
    @Test func currentPortsHaveAKind() {
        for port in SerialPortCatalog.currentPorts() {
            if port.name == "Bluetooth-Incoming-Port" || port.name == "debug-console" { #expect(port.kind == .system) }
        }
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
