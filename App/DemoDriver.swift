#if DEBUG
import Foundation
import GPSLoggerKit
import LoggerCore

/// Simulated driver for exercising the session UI without hardware (task 7.3). Debug builds only.
struct DemoDriver: LoggerDriver {
    enum Scenario: String, CaseIterable, Sendable {
        case success
        case failure
        case timeout
        case empty
    }

    let scenario: Scenario
    let erase: EraseSupport

    var descriptor: DriverDescriptor {
        DriverDescriptor(id: "demo.\(scenario.rawValue)", name: "Demo Logger", eraseSupport: erase,
                         activityTimeout: scenario == .timeout ? 3 : 30)
    }

    var resourceKey: String { "/dev/cu.demo" }

    func read(_ context: DriverContext) async throws -> Recording {
        let source = resourceKey
        context.diagnostics.record(.event(source: source, name: DiagnosticEventName.open, detail: "demo"))
        defer { context.diagnostics.record(.event(source: source, name: DiagnosticEventName.close, detail: nil)) }

        switch scenario {
        case .success:
            context.progress(.indeterminate(step: "Connecting"))
            try await pause(0.5)
            let total = 200
            var points: [TrackPoint] = []
            let start = Date().addingTimeInterval(-3600)
            for index in 0..<total {
                let command = Array("$PT,\(index)\r\n".utf8)
                context.diagnostics.record(.transmitted(source: source, bytes: command))
                let latitude = 51.74 + Double(index) * 0.0002
                let longitude = 8.68 + Double(index) * 0.0003
                context.diagnostics.record(.received(source: source,
                                                     bytes: Array("$PT,\(index),\(latitude),\(longitude)\r\n".utf8)))
                points.append(TrackPoint(latitude: latitude, longitude: longitude, elevation: 94 + Double(index % 20),
                                         time: start.addingTimeInterval(Double(index) * 10)))
                if index % 10 == 0 {
                    context.progress(.determinate(completed: index, total: total, step: "Reading track points"))
                    try await pause(0.05)
                }
            }
            context.progress(.determinate(completed: total, total: total, step: "Reading track points"))
            return Recording(tracks: [Track(name: "Demo", segments: [TrackSegment(points: points)])],
                             waypoints: [Waypoint(latitude: 51.75, longitude: 8.69, time: start, name: "WPT")])

        case .failure:
            context.progress(.indeterminate(step: "Connecting"))
            try await pause(0.5)
            throw LoggerError(.protocolError, detail: "Demo: checksum mismatch in line 17")

        case .timeout:
            context.progress(.indeterminate(step: "Waiting for the device"))
            try await pause(60)
            return Recording()

        case .empty:
            context.progress(.indeterminate(step: "Connecting"))
            try await pause(0.5)
            return Recording()
        }
    }

    func erase(_ context: DriverContext) async throws {
        context.progress(.determinate(completed: 0, total: 3, step: "Erasing"))
        for block in 1...3 {
            try await pause(0.5)
            context.progress(.determinate(completed: block, total: 3, step: "Erasing"))
        }
    }

    private func pause(_ seconds: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if Task.isCancelled { throw LoggerError(.cancelled) }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
#endif
