import Foundation
import Testing
import DeviceDrivers
import LoggerCore
@testable import HIDTransport

@Suite("USB HID transport")
struct HIDTransportTests {
    private var entry: DeviceEntry { DeviceCatalog.entry(withID: "igotu.gt-120")! }

    @Test func resourceKey() {
        #expect(IOKitHIDConnectionFactory().resourceKey(for: entry) == "hid:0df7:0900")
    }

    /// Without an i-GotU attached, opening fails with "device not found" (no hardware on build machines).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GPSLOADER_IGOTU_ATTACHED"] == nil))
    func noDeviceAttached() async {
        await #expect(throws: LoggerError.self) {
            _ = try await IOKitHIDConnectionFactory().open(entry, diagnostics: NullSink())
        }
    }

    @Test func inputBuffer() {
        let buffer = HIDInputBuffer()
        [UInt8]([1, 2, 3]).withUnsafeBufferPointer { buffer.append($0) }
        #expect(buffer.take(4) == nil && buffer.take(2) == [1, 2] && buffer.available == 1)
        buffer.removeAll()
        #expect(buffer.available == 0)
    }
}
