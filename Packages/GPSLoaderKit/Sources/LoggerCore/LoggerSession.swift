import Foundation
import GPSLoggerKit

public enum SessionOperation: Sendable, Equatable {
    case read
    case erase
}

/// Why a session refused to start an operation.
public enum SessionRejection: Sendable, Equatable {
    /// Another operation is using the same port or device.
    case busy(resource: String)
    /// The driver cannot erase.
    case eraseNotSupported
    /// The driver's erase is experimental and the user has not acknowledged the warning.
    case experimentalNotAcknowledged
}

/// The result of an operation.
public enum SessionOutcome: Sendable, Equatable {
    case recording(Recording)
    /// Read succeeded, but the logger holds no data. Nothing must be written.
    case emptyDevice
    case erased
    case failed(LoggerError)
    case cancelled
    case rejected(SessionRejection)
}

/// Events for the UI.
public enum SessionEvent: Sendable, Equatable {
    case started(SessionOperation)
    case progress(ProgressUpdate)
    case finished(SessionOutcome)
}

/// Proof that the user explicitly confirmed erasing (spec `logger-session`, "Bestätigung vor dem Löschen").
/// Only create it as the result of a confirmation dialog.
public struct EraseConfirmation: Sendable, Equatable {
    public let acknowledgesExperimentalErase: Bool

    private init(acknowledgesExperimentalErase: Bool) {
        self.acknowledgesExperimentalErase = acknowledgesExperimentalErase
    }

    /// The user confirmed the irreversible erase. Pass `true` for `acknowledgingExperimentalErase`
    /// only when the dialog also showed the warning for experimental drivers.
    public static func confirmedByUser(acknowledgingExperimentalErase: Bool = false) -> EraseConfirmation {
        EraseConfirmation(acknowledgesExperimentalErase: acknowledgingExperimentalErase)
    }
}

/// Runs read and erase operations on one driver (spec `logger-session`).
///
/// - Progress and the final outcome are published on `events`.
/// - `cancel()` can be called from any thread; the driver gets `cancellationGrace` seconds to
///   release its resources, partial results are discarded.
/// - If the driver reports no activity for `descriptor.activityTimeout`, the operation ends with
///   `.timeout`.
/// - A `PortReservations` registry prevents two operations on the same resource.
public actor LoggerSession {
    public nonisolated let events: AsyncStream<SessionEvent>
    private nonisolated let continuation: AsyncStream<SessionEvent>.Continuation

    public nonisolated let driver: any LoggerDriver
    private let reservations: PortReservations
    private let diagnostics: any DiagnosticSink
    private let cancellationGrace: TimeInterval
    private nonisolated let cancelRequested = Locked(false)

    public init(driver: any LoggerDriver,
                reservations: PortReservations,
                diagnostics: any DiagnosticSink = NullSink(),
                cancellationGrace: TimeInterval = 5) {
        self.driver = driver
        self.reservations = reservations
        self.diagnostics = diagnostics
        self.cancellationGrace = cancellationGrace
        (events, continuation) = AsyncStream.makeStream(of: SessionEvent.self)
    }

    /// Reads the device. Returns `.recording`, `.emptyDevice`, `.failed`, `.cancelled` or `.rejected(.busy)`.
    public func read() async -> SessionOutcome {
        let driver = self.driver
        return await run(.read) { context in
            let recording = try await driver.read(context)
            return recording.isEmpty ? .emptyDevice : .recording(recording)
        }
    }

    /// Erases the device after the user confirmed it.
    public func erase(_ confirmation: EraseConfirmation) async -> SessionOutcome {
        switch driver.descriptor.eraseSupport {
        case .unsupported:
            return finish(.rejected(.eraseNotSupported))
        case .experimental where !confirmation.acknowledgesExperimentalErase:
            return finish(.rejected(.experimentalNotAcknowledged))
        case .supported, .experimental:
            let driver = self.driver
            return await run(.erase) { context in
                try await driver.erase(context)
                return .erased
            }
        }
    }

    /// Requests cancellation of the running operation.
    public nonisolated func cancel() {
        cancelRequested.withLock { $0 = true }
        diagnostics.record(.event(source: "session", name: DiagnosticEventName.cancel, detail: nil))
    }

    // MARK: - Running

    private enum Race: Sendable {
        case done(Result<SessionOutcome, any Error>)
        case timedOut
        case cancelRequested
    }

    private func run(_ operation: SessionOperation,
                     body: @escaping @Sendable (DriverContext) async throws -> SessionOutcome) async -> SessionOutcome {
        let key = driver.resourceKey
        guard await reservations.reserve(key) else {
            return finish(.rejected(.busy(resource: key)))
        }
        cancelRequested.withLock { $0 = false }
        continuation.yield(.started(operation))

        let lastActivity = Locked(Date())
        let continuation = self.continuation
        let context = DriverContext(
            progress: { update in
                lastActivity.withLock { $0 = Date() }
                continuation.yield(.progress(update))
            },
            activity: { lastActivity.withLock { $0 = Date() } },
            diagnostics: diagnostics
        )

        let work = Task { try await body(context) }
        let race = await Self.race(work: work,
                                   lastActivity: lastActivity,
                                   activityTimeout: driver.descriptor.activityTimeout,
                                   cancelRequested: cancelRequested)

        let outcome: SessionOutcome
        switch race {
        case let .done(.success(value)):
            outcome = value
        case let .done(.failure(error)):
            outcome = Self.outcome(for: error)
        case .timedOut:
            work.cancel()
            _ = await Self.wait(for: work, upTo: cancellationGrace)
            diagnostics.record(.event(source: "session", name: DiagnosticEventName.timeout, detail: nil))
            outcome = .failed(LoggerError(.timeout,
                                          detail: "No activity for \(Int(driver.descriptor.activityTimeout)) s"))
        case .cancelRequested:
            work.cancel()
            _ = await Self.wait(for: work, upTo: cancellationGrace)
            outcome = .cancelled
        }

        await reservations.release(key)
        return finish(outcome)
    }

    private func finish(_ outcome: SessionOutcome) -> SessionOutcome {
        if case let .failed(error) = outcome {
            diagnostics.record(.event(source: "session", name: DiagnosticEventName.error,
                                      detail: "\(error.kind.rawValue): \(error.detail)"))
        }
        continuation.yield(.finished(outcome))
        return outcome
    }

    private static func outcome(for error: any Error) -> SessionOutcome {
        if error is CancellationError {
            return .cancelled
        }
        if let loggerError = error as? LoggerError {
            return loggerError.kind == .cancelled ? .cancelled : .failed(loggerError)
        }
        return .failed(LoggerError(.protocolError, detail: String(describing: error)))
    }

    /// Waits for whichever happens first: the work finishes, the activity timeout expires, or
    /// cancellation is requested.
    private static func race(work: Task<SessionOutcome, any Error>,
                             lastActivity: Locked<Date>,
                             activityTimeout: TimeInterval,
                             cancelRequested: Locked<Bool>) async -> Race {
        let resolved = Locked(false)
        return await withCheckedContinuation { (raceContinuation: CheckedContinuation<Race, Never>) in
            let resolve: @Sendable (Race) -> Void = { result in
                let first = resolved.withLock { done -> Bool in
                    defer { done = true }
                    return !done
                }
                if first { raceContinuation.resume(returning: result) }
            }
            Task {
                do {
                    resolve(.done(.success(try await work.value)))
                } catch {
                    resolve(.done(.failure(error)))
                }
            }
            Task {
                while !resolved.current {
                    if cancelRequested.current {
                        resolve(.cancelRequested)
                        return
                    }
                    if Date().timeIntervalSince(lastActivity.current) > activityTimeout {
                        resolve(.timedOut)
                        return
                    }
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
            }
        }
    }

    /// Waits until `work` has finished, at most `seconds`. Returns `true` if it finished.
    private static func wait(for work: Task<SessionOutcome, any Error>, upTo seconds: TimeInterval) async -> Bool {
        let resolved = Locked(false)
        return await withCheckedContinuation { (waitContinuation: CheckedContinuation<Bool, Never>) in
            let resolve: @Sendable (Bool) -> Void = { finished in
                let first = resolved.withLock { done -> Bool in
                    defer { done = true }
                    return !done
                }
                if first { waitContinuation.resume(returning: finished) }
            }
            Task {
                _ = await work.result
                resolve(true)
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                resolve(false)
            }
        }
    }
}
