import Foundation
import LoggerCore

/// A driver whose behavior is defined by closures. For session and UI tests.
public struct ClosureDriver: LoggerDriver {
    public var descriptor: DriverDescriptor
    public var resourceKey: String
    private let readBody: @Sendable (DriverContext) async throws -> Recording
    private let eraseBody: @Sendable (DriverContext) async throws -> Void

    public init(descriptor: DriverDescriptor = DriverDescriptor(id: "test", name: "Test", eraseSupport: .supported),
                resourceKey: String = "/dev/cu.test",
                read: @escaping @Sendable (DriverContext) async throws -> Recording = { _ in Recording() },
                erase: @escaping @Sendable (DriverContext) async throws -> Void = { _ in }) {
        self.descriptor = descriptor
        self.resourceKey = resourceKey
        self.readBody = read
        self.eraseBody = erase
    }

    public func read(_ context: DriverContext) async throws -> Recording {
        try await readBody(context)
    }

    public func erase(_ context: DriverContext) async throws {
        try await eraseBody(context)
    }
}

/// Sleeps in small steps and throws `LoggerError(.cancelled)` on cancellation.
public func cancellableSleep(_ seconds: TimeInterval) async throws {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if Task.isCancelled { throw LoggerError(.cancelled) }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

/// Collects all events of a session until `.finished` arrives.
public func collectEvents(_ events: AsyncStream<SessionEvent>) async -> [SessionEvent] {
    var collected: [SessionEvent] = []
    for await event in events {
        collected.append(event)
        if case .finished = event { break }
    }
    return collected
}
