import Darwin
import Foundation
import LoggerCore

/// Where the bundled gpsbabel lives (design.md D5).
public struct GPSBabelLocation: Sendable, Equatable {
    public static let requiredVersion = "1.7.0"

    /// `Contents/Helpers/gpsbabel`
    public var executableURL: URL
    /// `Contents/Frameworks/QtCoreGpsBabel.framework`
    public var frameworkURL: URL

    public init(executableURL: URL, frameworkURL: URL) {
        self.executableURL = executableURL
        self.frameworkURL = frameworkURL
    }

    /// The gpsbabel inside an app bundle. Never looks at `PATH`.
    public static func bundled(in bundleURL: URL) -> GPSBabelLocation {
        let contents = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        return GPSBabelLocation(
            executableURL: contents.appendingPathComponent("Helpers/gpsbabel"),
            frameworkURL: contents.appendingPathComponent("Frameworks/QtCoreGpsBabel.framework", isDirectory: true)
        )
    }
}

/// Result of checking the gpsbabel runtime (spec `gpsbabel-runtime`, "Prüfung der Laufzeit").
public enum GPSBabelStatus: Sendable, Equatable {
    case checking
    case ready(version: String)
    case rosettaMissing
    case broken(reason: String)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

/// Facts about the hardware the app runs on.
public enum HostArchitecture {
    /// `true` on Apple silicon, also when this process itself runs under Rosetta.
    public static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 else { return false }
        return value == 1
    }
}

/// Runs the bundled gpsbabel and maps failures to `LoggerError`.
public struct GPSBabelRunner: Sendable {
    public let location: GPSBabelLocation
    private let runner: ProcessRunner

    public init(location: GPSBabelLocation, diagnostics: any DiagnosticSink = NullSink(),
                registry: ProcessRegistry = .shared) {
        self.location = location
        self.runner = ProcessRunner(executableURL: location.executableURL, diagnostics: diagnostics, registry: registry)
    }

    /// Runs gpsbabel with `arguments`.
    ///
    /// - Throws: `.rosettaMissing` if the x86_64 binary cannot start, `.gpsbabelFailed` with stderr for a
    ///   non-zero exit code or another start failure, `.timeout`, `.cancelled`.
    public func run(_ arguments: [String], in directory: URL? = nil, timeout: TimeInterval) async throws -> ProcessOutput {
        let output: ProcessOutput
        do {
            output = try await runner.run(arguments, in: directory, timeout: timeout)
        } catch let error as ProcessLaunchError {
            if error.isBadArchitecture {
                throw LoggerError(.rosettaMissing, detail: error.description)
            }
            throw LoggerError(.gpsbabelFailed, detail: error.description)
        }
        guard output.exitCode == 0 else {
            let detail = output.standardError.isEmpty ? "exit code \(output.exitCode)" : output.standardError
            throw LoggerError(.gpsbabelFailed, detail: detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }
}

/// Checks whether gpsbabel can run (design.md D6).
public struct GPSBabelProbe: Sendable {
    public static let defaultTimeout: TimeInterval = 30

    public let location: GPSBabelLocation
    public let isAppleSilicon: Bool
    public let timeout: TimeInterval
    /// Starts the process; replaceable in tests.
    private let launch: @Sendable (URL, [String], TimeInterval) async throws -> ProcessOutput

    public init(location: GPSBabelLocation,
                isAppleSilicon: Bool = HostArchitecture.isAppleSilicon,
                timeout: TimeInterval = GPSBabelProbe.defaultTimeout,
                launch: (@Sendable (URL, [String], TimeInterval) async throws -> ProcessOutput)? = nil) {
        self.location = location
        self.isAppleSilicon = isAppleSilicon
        self.timeout = timeout
        self.launch = launch ?? { url, arguments, timeout in
            try await ProcessRunner(executableURL: url).run(arguments, timeout: timeout)
        }
    }

    public func check() async -> GPSBabelStatus {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: location.executableURL.path) else {
            return .broken(reason: "gpsbabel not found at \(location.executableURL.path)")
        }
        guard fileManager.fileExists(atPath: location.frameworkURL.path) else {
            return .broken(reason: "QtCoreGpsBabel.framework not found at \(location.frameworkURL.path)")
        }

        let output: ProcessOutput
        do {
            output = try await launch(location.executableURL, ["-V"], timeout)
        } catch let error as ProcessLaunchError {
            if error.isBadArchitecture && isAppleSilicon {
                return .rosettaMissing
            }
            return .broken(reason: error.description)
        } catch let error as LoggerError {
            return .broken(reason: "\(error.kind.rawValue): \(error.detail)")
        } catch {
            return .broken(reason: String(describing: error))
        }

        guard output.exitCode == 0 else {
            let message = output.standardError.isEmpty ? output.standardOutput : output.standardError
            return .broken(reason: "gpsbabel -V failed (exit code \(output.exitCode)): "
                + message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let version = Self.version(in: output.standardOutput + output.standardError) else {
            return .broken(reason: "Unexpected output of gpsbabel -V: \(output.standardOutput)")
        }
        guard version == GPSBabelLocation.requiredVersion else {
            return .broken(reason: "gpsbabel \(version) found, \(GPSBabelLocation.requiredVersion) required")
        }
        return .ready(version: version)
    }

    /// Extracts "1.7.0" from "GPSBabel Version 1.7.0".
    static func version(in text: String) -> String? {
        guard let range = text.range(of: "GPSBabel Version ") else { return nil }
        let rest = text[range.upperBound...]
        let version = rest.prefix { $0.isNumber || $0 == "." }
        return version.isEmpty ? nil : String(version)
    }
}

/// Caches the runtime status and re-checks it before every gpsbabel operation
/// (spec `gpsbabel-runtime`, "Prüfung der Laufzeit" and "Kein Start ohne Rosetta").
public actor GPSBabelRuntime {
    public let probe: GPSBabelProbe
    public private(set) var status: GPSBabelStatus = .checking
    private var running: Task<GPSBabelStatus, Never>?

    public init(probe: GPSBabelProbe) {
        self.probe = probe
    }

    /// Runs the probe (or joins a probe that is already running).
    @discardableResult
    public func refresh() async -> GPSBabelStatus {
        if let running {
            return await running.value
        }
        status = .checking
        let probe = self.probe
        let task = Task { await probe.check() }
        running = task
        let result = await task.value
        running = nil
        status = result
        return result
    }

    /// Call before every gpsbabel operation. Re-checks and throws when gpsbabel cannot run.
    public func ensureReady() async throws {
        let current = await refresh()
        switch current {
        case .ready:
            return
        case .rosettaMissing:
            throw LoggerError(.rosettaMissing)
        case let .broken(reason):
            throw LoggerError(.gpsbabelFailed, detail: reason)
        case .checking:
            throw LoggerError(.gpsbabelFailed, detail: "gpsbabel check did not finish")
        }
    }
}
