import Darwin
import Foundation
import Testing
import LoggerCore
@testable import GPSBabelRuntime

@Suite("ProcessRunner", .serialized)
struct ProcessRunnerTests {
    // MARK: Running (task 6.3)

    /// Scenario "Erfolgreicher Aufruf".
    @Test func capturesOutputOfSuccessfulRun() async throws {
        let output = try await ProcessRunner(executableURL: URL(fileURLWithPath: "/bin/echo"))
            .run(["hello"], timeout: 10)
        #expect(output == ProcessOutput(standardOutput: "hello\n", standardError: "", exitCode: 0))
    }

    /// Scenario "Fehlerhafter Aufruf".
    @Test func nonZeroExitIsGpsbabelFailedWithStderr() async throws {
        let directory = try TemporaryDirectory()
        let tool = try directory.makePerlExecutable("tool", body: #"print STDERR "cannot open /dev/cu.x\n"; exit 1;"#)
        let runner = GPSBabelRunner(location: GPSBabelLocation(executableURL: tool, frameworkURL: directory.url))
        await #expect(throws: LoggerError(.gpsbabelFailed, detail: "cannot open /dev/cu.x")) {
            _ = try await runner.run(["-i", "mtk"], timeout: 10)
        }
    }

    /// Scenario "Dateiname mit Sonderzeichen": one argument, no shell interpretation.
    @Test func argumentsArePassedUnchanged() async throws {
        let name = #"Tour "Süd" & Co; rm -rf.nmea"#
        let output = try await ProcessRunner(executableURL: URL(fileURLWithPath: "/bin/echo")).run([name], timeout: 10)
        #expect(output.standardOutput == name + "\n")

        let directory = try TemporaryDirectory()
        let counter = try directory.makePerlExecutable("count", body: #"print scalar(@ARGV), "|", join("|", @ARGV);"#)
        let counted = try await ProcessRunner(executableURL: counter).run(["-f", name, "$HOME", "*"], timeout: 10)
        #expect(counted.standardOutput == "4|-f|\(name)|$HOME|*")
    }

    /// Scenario "Nebenprodukt im Arbeitsverzeichnis".
    @Test func temporaryDirectoryHoldsSideProductsUntilTheEnd() async throws {
        let toucher = ProcessRunner(executableURL: URL(fileURLWithPath: "/usr/bin/touch"))
        let used = try await ProcessRunner.withTemporaryDirectory { directory -> URL in
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
            _ = try await toucher.run(["data.bin"], in: directory, timeout: 10)
            #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("data.bin").path))
            return directory
        }
        #expect(!FileManager.default.fileExists(atPath: used.path))
    }

    @Test func largeOutputDoesNotDeadlock() async throws {
        let directory = try TemporaryDirectory()
        let noisy = try directory.makePerlExecutable("noisy", body: #"print STDERR ("x" x 1048576); print ("y" x 1048576);"#)
        let output = try await ProcessRunner(executableURL: noisy).run([], timeout: 20)
        #expect(output.standardError.count == 1_048_576)
        #expect(output.standardOutput.count == 1_048_576)
    }

    @Test func invocationIsRecordedForDiagnostics() async throws {
        let sink = RecordingSink()
        _ = try await ProcessRunner(executableURL: URL(fileURLWithPath: "/bin/echo"), diagnostics: sink)
            .run(["-f", "a b"], timeout: 10)
        guard case let .process(record)? = sink.events.first else {
            Issue.record("no process record")
            return
        }
        #expect(record.executable == "/bin/echo")
        #expect(record.arguments == ["-f", "a b"])
        #expect(record.standardOutput == "-f a b\n")
        #expect(record.exitCode == 0)
    }

    @Test func missingExecutableIsLaunchError() async {
        await #expect(throws: ProcessLaunchError.self) {
            _ = try await ProcessRunner(executableURL: URL(fileURLWithPath: "/nonexistent/gpsbabel")).run([], timeout: 5)
        }
    }

    @Test func environmentContainsNoDyldVariables() async throws {
        let output = try await ProcessRunner(executableURL: URL(fileURLWithPath: "/usr/bin/env")).run([], timeout: 10)
        #expect(!output.standardOutput.contains("DYLD_"))
        #expect(output.standardOutput.contains("PATH=/usr/bin:/bin"))
    }

    // MARK: Cancellation and timeout (task 6.4)

    /// Scenario "Abbruch".
    @Test func cancellationTerminatesProcess() async throws {
        let registry = ProcessRegistry()
        let runner = ProcessRunner(executableURL: URL(fileURLWithPath: "/bin/sleep"), registry: registry)
        let task = Task { try await runner.run(["60"], timeout: 120) }
        try await Task.sleep(nanoseconds: 300_000_000)
        let pid = try #require(registry.runningProcesses.first)

        let cancelledAt = Date()
        task.cancel()
        await #expect(throws: LoggerError(.cancelled)) { _ = try await task.value }
        #expect(Date().timeIntervalSince(cancelledAt) <= 3)
        #expect(!processExists(pid))
        #expect(registry.runningProcesses.isEmpty)
    }

    @Test func processIgnoringSigtermIsKilled() async throws {
        let directory = try TemporaryDirectory()
        let stubborn = try directory.makePerlExecutable("stubborn", body: #"$SIG{TERM} = "IGNORE"; sleep 60;"#)
        let registry = ProcessRegistry()
        let runner = ProcessRunner(executableURL: stubborn, registry: registry, terminationGrace: 0.5)
        let task = Task { try await runner.run([], timeout: 120) }
        try await Task.sleep(nanoseconds: 300_000_000)
        let pid = try #require(registry.runningProcesses.first)

        let cancelledAt = Date()
        task.cancel()
        await #expect(throws: LoggerError(.cancelled)) { _ = try await task.value }
        #expect(Date().timeIntervalSince(cancelledAt) < 2)
        #expect(!processExists(pid))
    }

    @Test func timeoutTerminatesProcess() async throws {
        let start = Date()
        await #expect {
            _ = try await ProcessRunner(executableURL: URL(fileURLWithPath: "/bin/sleep")).run(["60"], timeout: 0.3)
        } throws: { error in
            (error as? LoggerError)?.kind == .timeout
        }
        #expect(Date().timeIntervalSince(start) < 3)
    }

    /// Scenario "App wird während eines Aufrufs beendet".
    @Test func registryTerminatesAllProcesses() async throws {
        let registry = ProcessRegistry()
        let runner = ProcessRunner(executableURL: URL(fileURLWithPath: "/bin/sleep"), registry: registry)
        let first = Task { try await runner.run(["60"], timeout: 120) }
        let second = Task { try await runner.run(["60"], timeout: 120) }
        try await Task.sleep(nanoseconds: 300_000_000)
        let pids = registry.runningProcesses
        #expect(pids.count == 2)

        await registry.terminateAll(grace: 1)
        #expect(registry.runningProcesses.isEmpty)
        for pid in pids { #expect(!processExists(pid)) }
        _ = await first.result
        _ = await second.result
    }
}
