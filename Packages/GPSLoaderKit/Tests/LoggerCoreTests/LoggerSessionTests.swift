import Foundation
import Testing
import TestSupport
@testable import LoggerCore

private let onePointRecording = Recording(tracks: [
    Track(name: "t", segments: [TrackSegment(points: [TrackPoint(latitude: 51, longitude: 8)])]),
])

private func descriptor(erase: EraseSupport = .supported, timeout: TimeInterval = 30) -> DriverDescriptor {
    DriverDescriptor(id: "test", name: "Test", eraseSupport: erase, activityTimeout: timeout)
}

@Suite("PortReservations")
struct PortReservationsTests {
    @Test func secondReservationIsRejectedUntilReleased() async {
        let reservations = PortReservations()
        #expect(await reservations.reserve("/dev/cu.a"))
        #expect(await !reservations.reserve("/dev/cu.a"))
        #expect(await reservations.reserve("/dev/cu.b"))
        await reservations.release("/dev/cu.a")
        #expect(await reservations.reserve("/dev/cu.a"))
    }
}

@Suite("LoggerSession")
struct LoggerSessionTests {
    // MARK: Reading

    @Test func successfulReadReturnsRecordingAndEvents() async {
        let driver = ClosureDriver(read: { context in
            context.progress(.determinate(completed: 250, total: 1000, step: nil))
            return onePointRecording
        })
        let session = LoggerSession(driver: driver, reservations: PortReservations())
        async let events = collectEvents(session.events)
        let outcome = await session.read()

        #expect(outcome == .recording(onePointRecording))
        let collected = await events
        #expect(collected.first == .started(.read))
        #expect(collected.contains(.progress(.determinate(completed: 250, total: 1000, step: nil))))
        #expect(collected.last == .finished(.recording(onePointRecording)))
    }

    /// Scenario "Bestimmter Fortschritt".
    @Test func determinateProgressFraction() {
        #expect(ProgressUpdate.determinate(completed: 250, total: 1000, step: nil).fraction == 0.25)
    }

    /// Scenario "Unbestimmter Fortschritt".
    @Test func indeterminateProgressHasStepButNoFraction() {
        let update = ProgressUpdate.indeterminate(step: "Waiting for device")
        #expect(update.fraction == nil)
        #expect(update.step == "Waiting for device")
    }

    /// Scenario "Keine Daten auf dem Gerät".
    @Test func emptyRecordingIsReportedAsEmptyDevice() async {
        let session = LoggerSession(driver: ClosureDriver(read: { _ in Recording() }), reservations: PortReservations())
        #expect(await session.read() == .emptyDevice)
    }

    // MARK: Cancellation

    /// Scenario "Abbruch beim Auslesen": the port is released and no data is returned.
    @Test func cancelReleasesTransportAndDiscardsData() async throws {
        let transport = MockTransport(script: [])
        let driver = ClosureDriver(resourceKey: transport.identifier, read: { context in
            try await transport.open()
            do {
                _ = try await transport.read(count: 100, timeout: 60)
            } catch {
                await transport.close()
                throw error
            }
            return onePointRecording
        })
        let reservations = PortReservations()
        let session = LoggerSession(driver: driver, reservations: reservations)
        let task = Task { await session.read() }
        try await Task.sleep(nanoseconds: 100_000_000)
        session.cancel()

        let outcome = await task.value
        #expect(outcome == .cancelled)
        #expect(await transport.closeCount == 1)
        #expect(await !reservations.isReserved(transport.identifier))
    }

    @Test func driverIgnoringCancellationIsAbandonedAfterGrace() async throws {
        let driver = ClosureDriver(read: { _ in
            // Ignores cancellation completely.
            let end = Date().addingTimeInterval(2)
            while Date() < end { try? await Task.sleep(nanoseconds: 10_000_000) }
            return onePointRecording
        })
        let session = LoggerSession(driver: driver, reservations: PortReservations(), cancellationGrace: 0.3)
        let start = Date()
        let task = Task { await session.read() }
        try await Task.sleep(nanoseconds: 50_000_000)
        session.cancel()
        #expect(await task.value == .cancelled)
        #expect(Date().timeIntervalSince(start) < 1.5)
    }

    // MARK: Timeout

    /// Scenario "Gerät antwortet nicht".
    @Test func noActivityEndsWithTimeout() async {
        let driver = ClosureDriver(descriptor: descriptor(timeout: 0.2), read: { _ in
            try await cancellableSleep(10)
            return onePointRecording
        })
        let session = LoggerSession(driver: driver, reservations: PortReservations(), cancellationGrace: 1)
        let outcome = await session.read()
        guard case let .failed(error) = outcome else {
            Issue.record("expected failure, got \(outcome)")
            return
        }
        #expect(error.kind == .timeout)
    }

    @Test func progressKeepsTheOperationAlive() async {
        let driver = ClosureDriver(descriptor: descriptor(timeout: 0.2), read: { context in
            for step in 0..<10 {
                try await cancellableSleep(0.05)
                context.progress(.determinate(completed: step, total: 10, step: nil))
            }
            return onePointRecording
        })
        let session = LoggerSession(driver: driver, reservations: PortReservations())
        #expect(await session.read() == .recording(onePointRecording))
    }

    // MARK: Errors

    /// Scenario "Port belegt".
    @Test func loggerErrorsArePassedThrough() async {
        let error = LoggerError(.portBusy, detail: "/dev/cu.SLAB_USBtoUART")
        let session = LoggerSession(driver: ClosureDriver(read: { _ in throw error }), reservations: PortReservations())
        #expect(await session.read() == .failed(error))
    }

    @Test func unknownErrorsBecomeProtocolErrors() async {
        struct Strange: Error {}
        let session = LoggerSession(driver: ClosureDriver(read: { _ in throw Strange() }), reservations: PortReservations())
        guard case let .failed(error) = await session.read() else {
            Issue.record("expected failure")
            return
        }
        #expect(error.kind == .protocolError)
    }

    // MARK: Exclusivity

    /// Scenario "Zweiter Start während laufendem Vorgang".
    @Test func secondOperationOnSamePortIsRejected() async throws {
        let reservations = PortReservations()
        let slow = ClosureDriver(read: { _ in
            try await cancellableSleep(1)
            return onePointRecording
        })
        let first = LoggerSession(driver: slow, reservations: reservations)
        let second = LoggerSession(driver: ClosureDriver(), reservations: reservations)
        let running = Task { await first.read() }
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(await second.read() == .rejected(.busy(resource: "/dev/cu.test")))
        first.cancel()
        _ = await running.value
    }

    // MARK: Erasing

    /// Scenario "Treiber ohne Löschfunktion".
    @Test func eraseIsRejectedWhenUnsupported() async {
        let erased = Locked(false)
        let driver = ClosureDriver(descriptor: descriptor(erase: .unsupported), erase: { _ in erased.withLock { $0 = true } })
        let session = LoggerSession(driver: driver, reservations: PortReservations())
        #expect(await session.erase(.confirmedByUser()) == .rejected(.eraseNotSupported))
        #expect(!erased.current)
    }

    /// Scenario "Experimentelles Löschen": without acknowledging the warning nothing is sent.
    @Test func experimentalEraseNeedsAcknowledgement() async {
        let erased = Locked(false)
        let driver = ClosureDriver(descriptor: descriptor(erase: .experimental), erase: { _ in erased.withLock { $0 = true } })
        let session = LoggerSession(driver: driver, reservations: PortReservations())

        #expect(await session.erase(.confirmedByUser()) == .rejected(.experimentalNotAcknowledged))
        #expect(!erased.current)

        #expect(await session.erase(.confirmedByUser(acknowledgingExperimentalErase: true)) == .erased)
        #expect(erased.current)
    }

    /// Scenario "Löschen bestätigt".
    @Test func confirmedEraseSucceeds() async {
        let session = LoggerSession(driver: ClosureDriver(), reservations: PortReservations())
        #expect(await session.erase(.confirmedByUser()) == .erased)
    }
}
