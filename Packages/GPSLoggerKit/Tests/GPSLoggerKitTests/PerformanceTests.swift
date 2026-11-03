import Foundation
import Testing
@testable import GPSLoggerKit

/// Opt-in load test (task 7.3): reads the NMEA file named in `GPSLOGGERKIT_PERF_FILE` and reports
/// time and peak memory footprint. On the iOS simulator pass it as `TEST_RUNNER_GPSLOGGERKIT_PERF_FILE`.
@Suite("Performance")
struct PerformanceTests {
    static let file = ProcessInfo.processInfo.environment["GPSLOGGERKIT_PERF_FILE"]

    @Test(.enabled(if: file != nil))
    func largeNMEAFile() throws {
        let baseline = Self.currentFootprint()
        let start = Date()
        let input = try FileInput.load(URL(fileURLWithPath: Self.file!))
        let result = try FileFormats.readSynchronously([input], format: NMEAFileFormat())
        let elapsed = Date().timeIntervalSince(start)
        let peak = Self.peakFootprint()
        let growth = peak > baseline ? peak - baseline : 0
        print("PERF points=\(result.recording.trackPointCount) seconds=\(String(format: "%.2f", elapsed)) "
              + "baselineMB=\(baseline / 1_048_576) peakMB=\(peak / 1_048_576) growthMB=\(growth / 1_048_576)")
        #expect(result.recording.trackPointCount > 0)
        #if os(iOS)
        // iOS enforces memory limits on the footprint. On macOS the value is only reported: test builds use
        // -enable-testing and need noticeably more memory than a release app (see design.md D5).
        #expect(growth < 200 * 1_048_576)
        #endif
    }

    /// Peak physical footprint of this process (what iOS uses for memory limits).
    static func peakFootprint() -> UInt64 { vmInfo().map { UInt64(max(0, $0.ledger_phys_footprint_peak)) } ?? 0 }

    /// Current physical footprint of this process.
    static func currentFootprint() -> UInt64 { vmInfo().map { UInt64($0.phys_footprint) } ?? 0 }

    static func vmInfo() -> task_vm_info_data_t? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }
}
