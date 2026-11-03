import Darwin
import Foundation
import LoggerCore

/// Collects diagnostic events in memory.
final class RecordingSink: DiagnosticSink {
    private let storage = Locked<[DiagnosticEvent]>([])
    func record(_ event: DiagnosticEvent) { storage.withLock { $0.append(event) } }
    var events: [DiagnosticEvent] { storage.current }
}

/// A temporary directory that is removed on deinit.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("gpsloader-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Writes an executable Perl script (no shell involved).
    @discardableResult
    func makePerlExecutable(_ relativePath: String, body: String) throws -> URL {
        let file = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/usr/bin/perl\n\(body)\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }

    /// Creates a fake app bundle with Helpers/gpsbabel and Frameworks/QtCoreGpsBabel.framework.
    func makeFakeBundle(gpsbabelBody: String, withFramework: Bool = true) throws -> URL {
        let bundle = url.appendingPathComponent("Fake.app")
        try makePerlExecutable("Fake.app/Contents/Helpers/gpsbabel", body: gpsbabelBody)
        if withFramework {
            try FileManager.default.createDirectory(
                at: bundle.appendingPathComponent("Contents/Frameworks/QtCoreGpsBabel.framework"),
                withIntermediateDirectories: true)
        }
        return bundle
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

/// `true` while a process with this PID exists.
func processExists(_ pid: pid_t) -> Bool {
    kill(pid, 0) == 0
}
