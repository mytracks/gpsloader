import Darwin
import Foundation
import Testing
import LoggerCore
@testable import GPSBabelRuntime

private let versionOutput = ProcessOutput(standardOutput: "\nGPSBabel Version 1.7.0\n\n", standardError: "", exitCode: 0)

private func launcher(_ result: Result<ProcessOutput, any Error>) -> @Sendable (URL, [String], TimeInterval) async throws -> ProcessOutput {
    { _, arguments, _ in
        #expect(arguments == ["-V"])
        return try result.get()
    }
}

private func badArchitecture(_ url: URL) -> ProcessLaunchError {
    ProcessLaunchError(executable: url.path, posixCode: EBADARCH, message: "Bad CPU type in executable")
}

@Suite("GPSBabel runtime check (task 6.5)")
struct GPSBabelProbeTests {
    private func bundle(_ directory: TemporaryDirectory, withFramework: Bool = true) throws -> GPSBabelLocation {
        GPSBabelLocation.bundled(in: try directory.makeFakeBundle(
            gpsbabelBody: #"print "\nGPSBabel Version 1.7.0\n\n";"#, withFramework: withFramework))
    }

    @Test func bundledLocationIsInsideTheApp() {
        let location = GPSBabelLocation.bundled(in: URL(fileURLWithPath: "/Applications/gpsloader.app"))
        #expect(location.executableURL.path == "/Applications/gpsloader.app/Contents/Helpers/gpsbabel")
        #expect(location.frameworkURL.path == "/Applications/gpsloader.app/Contents/Frameworks/QtCoreGpsBabel.framework")
    }

    /// Scenario "Apple Silicon mit Rosetta" (simulated by a working executable).
    @Test func workingGpsbabelIsReady() async throws {
        let directory = try TemporaryDirectory()
        let probe = GPSBabelProbe(location: try bundle(directory), isAppleSilicon: true)
        #expect(await probe.check() == .ready(version: "1.7.0"))
    }

    /// Scenario "Apple Silicon ohne Rosetta".
    @Test func badArchitectureOnAppleSiliconMeansRosettaMissing() async throws {
        let directory = try TemporaryDirectory()
        let location = try bundle(directory)
        let probe = GPSBabelProbe(location: location, isAppleSilicon: true,
                                  launch: launcher(.failure(badArchitecture(location.executableURL))))
        #expect(await probe.check() == .rosettaMissing)
    }

    /// Scenario "Intel-Mac": Rosetta is irrelevant, a bad architecture means a broken bundle.
    @Test func badArchitectureOnIntelIsBroken() async throws {
        let directory = try TemporaryDirectory()
        let location = try bundle(directory)
        let probe = GPSBabelProbe(location: location, isAppleSilicon: false,
                                  launch: launcher(.failure(badArchitecture(location.executableURL))))
        guard case .broken = await probe.check() else {
            Issue.record("expected broken")
            return
        }
    }

    @Test func intelWithWorkingGpsbabelIsReady() async throws {
        let directory = try TemporaryDirectory()
        let probe = GPSBabelProbe(location: try bundle(directory), isAppleSilicon: false, launch: launcher(.success(versionOutput)))
        #expect(await probe.check() == .ready(version: "1.7.0"))
    }

    /// Scenario "Beschädigtes Bundle".
    @Test func missingExecutableOrFrameworkIsBroken() async throws {
        let directory = try TemporaryDirectory()
        let missing = GPSBabelLocation.bundled(in: directory.url.appendingPathComponent("Nothing.app"))
        guard case let .broken(reason) = await GPSBabelProbe(location: missing).check() else {
            Issue.record("expected broken")
            return
        }
        #expect(reason.contains("gpsbabel not found"))

        let noFramework = try bundle(directory, withFramework: false)
        guard case let .broken(frameworkReason) = await GPSBabelProbe(location: noFramework).check() else {
            Issue.record("expected broken")
            return
        }
        #expect(frameworkReason.contains("QtCoreGpsBabel.framework"))
    }

    @Test func libraryLoadFailureIsBroken() async throws {
        let directory = try TemporaryDirectory()
        let dyldFailure = ProcessOutput(standardOutput: "", standardError: "dyld: Library not loaded: QtCoreGpsBabel", exitCode: 134)
        let probe = GPSBabelProbe(location: try bundle(directory), launch: launcher(.success(dyldFailure)))
        guard case let .broken(reason) = await probe.check() else {
            Issue.record("expected broken")
            return
        }
        #expect(reason.contains("Library not loaded"))
    }

    /// Scenario "Versionsprüfung".
    @Test func otherVersionIsBroken() async throws {
        let directory = try TemporaryDirectory()
        let other = ProcessOutput(standardOutput: "GPSBabel Version 1.10.0\n", standardError: "", exitCode: 0)
        let probe = GPSBabelProbe(location: try bundle(directory), launch: launcher(.success(other)))
        #expect(await probe.check() == .broken(reason: "gpsbabel 1.10.0 found, 1.7.0 required"))
    }

    /// Scenario "gpsbabel im System vorhanden": a gpsbabel in PATH is never used.
    @Test func gpsbabelInPathIsIgnored() async throws {
        let directory = try TemporaryDirectory()
        try directory.makePerlExecutable("bin/gpsbabel", body: #"print "GPSBabel Version 9.9.9\n";"#)
        let oldPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        setenv("PATH", directory.url.appendingPathComponent("bin").path + ":" + oldPath, 1)
        defer { setenv("PATH", oldPath, 1) }

        let probe = GPSBabelProbe(location: try bundle(directory), isAppleSilicon: true)
        #expect(await probe.check() == .ready(version: "1.7.0"))
    }

    @Test func versionParsing() {
        #expect(GPSBabelProbe.version(in: "\nGPSBabel Version 1.7.0\n") == "1.7.0")
        #expect(GPSBabelProbe.version(in: "something else") == nil)
    }

    // MARK: Runtime cache and "Kein Start ohne Rosetta"

    /// Scenario "Auslesen über gpsbabel ohne Rosetta".
    @Test func ensureReadyThrowsWhenRosettaIsMissing() async throws {
        let directory = try TemporaryDirectory()
        let location = try bundle(directory)
        let runtime = GPSBabelRuntime(probe: GPSBabelProbe(location: location, isAppleSilicon: true,
                                                           launch: launcher(.failure(badArchitecture(location.executableURL)))))
        await #expect(throws: LoggerError(.rosettaMissing)) { try await runtime.ensureReady() }
        #expect(await runtime.status == .rosettaMissing)
    }

    @Test func ensureReadyPassesWhenReady() async throws {
        let directory = try TemporaryDirectory()
        let runtime = GPSBabelRuntime(probe: GPSBabelProbe(location: try bundle(directory)))
        try await runtime.ensureReady()
        #expect(await runtime.status == .ready(version: "1.7.0"))
    }

    @Test func runnerMapsBadArchitectureToRosettaMissing() async throws {
        // The real x86_64 gpsbabel from Vendor on a Mac without Rosetta, or a fake when that is not applicable.
        let vendor = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Vendor/gpsbabel-1.7.0/gpsbabel")
        guard HostArchitecture.isAppleSilicon, FileManager.default.fileExists(atPath: vendor.path) else { return }
        let runner = GPSBabelRunner(location: GPSBabelLocation(executableURL: vendor, frameworkURL: vendor))
        let rosettaInstalled = FileManager.default.fileExists(atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime")
        do {
            _ = try await runner.run(["-V"], timeout: 30)
            #expect(rosettaInstalled, "without Rosetta the x86_64 gpsbabel must not start")
        } catch let error as LoggerError {
            if rosettaInstalled {
                // gpsbabel starts but cannot find its framework outside an app bundle.
                #expect(error.kind == .gpsbabelFailed)
            } else {
                #expect(error.kind == .rosettaMissing)
            }
        }
    }
}
