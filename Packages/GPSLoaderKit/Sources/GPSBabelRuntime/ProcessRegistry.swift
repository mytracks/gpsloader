import Darwin
import Foundation
import LoggerCore

/// App-wide register of running child processes, so they can be terminated before the app quits
/// (spec `gpsbabel-runtime`, "Abbruch und Zeitlimit für gpsbabel").
public final class ProcessRegistry: Sendable {
    public static let shared = ProcessRegistry()

    private let running = Locked<Set<pid_t>>([])

    public init() {}

    func add(_ pid: pid_t) {
        running.withLock { _ = $0.insert(pid) }
    }

    func remove(_ pid: pid_t) {
        running.withLock { _ = $0.remove(pid) }
    }

    /// PIDs of processes that are still running.
    public var runningProcesses: Set<pid_t> {
        running.current
    }

    /// Sends SIGTERM to all registered processes, waits up to `grace` seconds and then sends SIGKILL to
    /// the remaining ones. Returns when all processes are gone or the escalation is done.
    public func terminateAll(grace: TimeInterval = 3) async {
        let pids = running.current
        guard !pids.isEmpty else { return }
        for pid in pids { kill(pid, SIGTERM) }
        let deadline = Date().addingTimeInterval(grace)
        while !running.current.isEmpty, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        for pid in running.current { kill(pid, SIGKILL) }
        let hardDeadline = Date().addingTimeInterval(1)
        while !running.current.isEmpty, Date() < hardDeadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
