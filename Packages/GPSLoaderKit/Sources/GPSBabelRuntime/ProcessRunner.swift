import Darwin
import Foundation
import LoggerCore

/// Output of a finished process.
public struct ProcessOutput: Sendable, Equatable {
    public var standardOutput: String
    public var standardError: String
    public var exitCode: Int32

    public init(standardOutput: String, standardError: String, exitCode: Int32) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.exitCode = exitCode
    }
}

/// Why a process could not be started.
public struct ProcessLaunchError: Error, Sendable, Equatable, CustomStringConvertible {
    public var executable: String
    /// POSIX error code if known (e.g. `EBADARCH` = 86 when Rosetta is missing).
    public var posixCode: Int32?
    public var message: String

    public var isBadArchitecture: Bool { posixCode == EBADARCH }

    public var description: String { "\(executable): \(message)" }
}

/// Runs an executable directly - never through a shell - with an argument array
/// (spec `gpsbabel-runtime`, "Sichere Ausführung").
///
/// - stdout, stderr and the exit code are captured.
/// - Cancellation and timeouts terminate the process: SIGTERM, then SIGKILL after `terminationGrace`.
/// - Running processes are tracked in a `ProcessRegistry`.
/// - Every invocation is reported to the diagnostic sink.
public struct ProcessRunner: Sendable {
    public let executableURL: URL
    public let diagnostics: any DiagnosticSink
    public let registry: ProcessRegistry
    public let terminationGrace: TimeInterval

    public init(executableURL: URL,
                diagnostics: any DiagnosticSink = NullSink(),
                registry: ProcessRegistry = .shared,
                terminationGrace: TimeInterval = 3) {
        self.executableURL = executableURL
        self.diagnostics = diagnostics
        self.registry = registry
        self.terminationGrace = terminationGrace
    }

    /// A minimal environment: no inherited `DYLD_*` or other variables that could change the behavior.
    public static var minimalEnvironment: [String: String] {
        var environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8"]
        let inherited = ProcessInfo.processInfo.environment
        for key in ["HOME", "TMPDIR", "USER"] {
            if let value = inherited[key] { environment[key] = value }
        }
        return environment
    }

    /// Runs the executable and waits for it to finish.
    ///
    /// - Throws: `ProcessLaunchError` if it cannot be started, `LoggerError(.timeout)` when `timeout`
    ///   expires, `LoggerError(.cancelled)` when the task is cancelled.
    ///   A non-zero exit code is *not* an error here; see `ProcessOutput.exitCode`.
    public func run(_ arguments: [String], in directory: URL? = nil, timeout: TimeInterval) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = Self.minimalEnvironment
        if let directory { process.currentDirectoryURL = directory }
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice

        // Start reading before the process runs, so a full pipe buffer can never block it.
        let outputReader = Self.startReading(outputPipe.fileHandleForReading)
        let errorReader = Self.startReading(errorPipe.fileHandleForReading)

        let start = Date()
        let state = Locked(RunState())
        let exitStatus = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, any Error>) in
                process.terminationHandler = { finished in
                    let status = finished.terminationStatus
                    state.withLock { $0.exited = true }
                    continuation.resume(returning: status)
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    Self.closeWriteEnds(outputPipe, errorPipe)
                    continuation.resume(throwing: launchError(error))
                    return
                }
                // The child has its own copies; closing ours lets the readers reach EOF.
                Self.closeWriteEnds(outputPipe, errorPipe)
                let pid = process.processIdentifier
                registry.add(pid)
                state.withLock { $0.pid = pid }
                // Timeout watchdog.
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    let expired = state.withLock { state -> Bool in
                        guard !state.exited, state.stopReason == nil else { return false }
                        state.stopReason = .timeout
                        return true
                    }
                    if expired {
                        terminate(pid: pid, state: state)
                    }
                }
                // A cancellation that arrived before the PID was known.
                if state.current.stopReason == .cancelled {
                    terminate(pid: pid, state: state)
                }
            }
        } onCancel: {
            let pid = state.withLock { state -> pid_t? in
                if state.stopReason == nil { state.stopReason = .cancelled }
                return state.exited ? nil : state.pid
            }
            if let pid { terminate(pid: pid, state: state) }
        }

        let pid = state.current.pid
        if let pid { registry.remove(pid) }

        // The pipes reach EOF once the process (and anything it spawned) has exited.
        let output = ProcessOutput(standardOutput: await outputReader.value, standardError: await errorReader.value,
                                   exitCode: exitStatus)

        diagnostics.record(.process(ProcessRecord(
            executable: executableURL.path, arguments: arguments,
            standardOutput: output.standardOutput, standardError: output.standardError,
            exitCode: exitStatus, duration: Date().timeIntervalSince(start))))

        switch state.current.stopReason {
        case .cancelled:
            throw LoggerError(.cancelled)
        case .timeout:
            throw LoggerError(.timeout, detail: "\(executableURL.lastPathComponent) did not finish within \(Int(timeout)) s")
        case nil:
            return output
        }
    }

    /// Runs `body` with a fresh, empty temporary directory that is removed afterwards
    /// (spec `gpsbabel-runtime`, "Arbeitsverzeichnis").
    public static func withTemporaryDirectory<T: Sendable>(_ body: (URL) async throws -> T) async throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gpsloader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try await body(directory)
    }

    // MARK: - Internals

    private enum StopReason: Sendable, Equatable {
        case cancelled
        case timeout
    }

    private struct RunState: Sendable {
        var pid: pid_t?
        var exited = false
        var stopReason: StopReason?
    }

    /// SIGTERM now, SIGKILL after the grace period if the process is still running.
    private func terminate(pid: pid_t, state: Locked<RunState>) {
        kill(pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + terminationGrace) {
            if !state.current.exited {
                kill(pid, SIGKILL)
            }
        }
    }

    private func launchError(_ error: any Error) -> ProcessLaunchError {
        let nsError = error as NSError
        let posixCode: Int32? = nsError.domain == NSPOSIXErrorDomain ? Int32(nsError.code) : nil
        return ProcessLaunchError(executable: executableURL.path, posixCode: posixCode,
                                  message: nsError.localizedDescription)
    }

    /// Reads a pipe to EOF on a background thread.
    private static func startReading(_ handle: FileHandle) -> Task<String, Never> {
        Task.detached {
            await withCheckedContinuation { continuation in
                DispatchQueue.global().async {
                    let data = (try? handle.readToEnd()) ?? Data()
                    continuation.resume(returning: String(decoding: data, as: UTF8.self))
                }
            }
        }
    }

    private static func closeWriteEnds(_ pipes: Pipe...) {
        for pipe in pipes {
            try? pipe.fileHandleForWriting.close()
        }
    }
}
