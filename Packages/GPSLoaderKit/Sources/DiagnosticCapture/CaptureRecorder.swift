import Darwin
import Foundation
import LoggerCore

/// Facts about the running app and system, written into the capture header.
public struct CaptureEnvironment: Sendable, Equatable {
    public var appVersion: String
    public var osVersion: String
    public var architecture: String
    public var isTranslated: Bool

    public init(appVersion: String, osVersion: String, architecture: String, isTranslated: Bool) {
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.architecture = architecture
        self.isTranslated = isTranslated
    }

    /// The environment of the current process.
    public static func current(appVersion: String) -> CaptureEnvironment {
        CaptureEnvironment(
            appVersion: appVersion,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: currentArchitecture,
            isTranslated: isRunningUnderRosetta
        )
    }

    static var currentArchitecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }

    /// `true` when this process runs translated by Rosetta.
    static var isRunningUnderRosetta: Bool {
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 else { return false }
        return translated == 1
    }
}

/// Records diagnostic events in memory (spec `diagnostic-capture`).
///
/// `record` is synchronous and thread safe, so the order of bytes on the wire is preserved exactly.
public final class CaptureRecorder: DiagnosticSink, Sendable {
    public let environment: CaptureEnvironment
    public let startDate: Date
    private let start: UInt64
    private let state = Locked<State>(State())

    private struct State: Sendable {
        var header: DiagnosticHeader?
        var lines: [CaptureLine] = []
    }

    public init(environment: CaptureEnvironment, startDate: Date = Date()) {
        self.environment = environment
        self.startDate = startDate
        self.start = DispatchTime.now().uptimeNanoseconds
    }

    public func record(_ event: DiagnosticEvent) {
        let elapsed = Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        state.withLock { state in
            if case let .header(header) = event {
                state.header = header
                return
            }
            var line = Self.line(for: event)
            line.t = elapsed
            state.lines.append(line)
        }
    }

    /// Driver name from the header, if one was recorded.
    public var driverName: String? {
        state.current.header?.driver
    }

    /// The entries recorded so far (without header).
    public var entries: [CaptureLine] {
        state.current.lines
    }

    /// The complete capture as JSON Lines.
    public func encoded() -> Data {
        let current = state.current
        return CaptureFormat.encode([headerLine(current.header)] + current.lines)
    }

    // MARK: - Mapping

    private func headerLine(_ header: DiagnosticHeader?) -> CaptureLine {
        var line = CaptureLine(kind: "header")
        line.format = CaptureFormat.identifier
        line.version = CaptureFormat.version
        line.created = ISO8601DateFormatter().string(from: startDate)
        line.app = environment.appVersion
        line.os = environment.osVersion
        line.arch = environment.architecture
        line.translated = environment.isTranslated
        line.driver = header?.driver
        line.port = header?.port
        line.params = header?.parameters
        return line
    }

    static func line(for event: DiagnosticEvent) -> CaptureLine {
        switch event {
        case .header:
            return CaptureLine(kind: "header")
        case let .transmitted(source, bytes):
            return byteLine(kind: "tx", source: source, bytes: bytes)
        case let .received(source, bytes):
            return byteLine(kind: "rx", source: source, bytes: bytes)
        case let .event(source, name, detail):
            var line = CaptureLine(kind: "event")
            line.source = source
            line.name = name
            line.detail = detail
            return line
        }
    }

    private static func byteLine(kind: String, source: String, bytes: [UInt8]) -> CaptureLine {
        var line = CaptureLine(kind: kind)
        line.source = source
        line.hex = bytes.hexString
        line.ascii = bytes.printableASCII
        return line
    }
}
