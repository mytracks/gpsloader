#if os(macOS)
import Foundation
@testable import GPSLoggerKit

/// Validates GPX data against the bundled GPX 1.1 XSD (no network access).
enum GPXSchemaValidator {
    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    static var schemaURL: URL {
        Bundle.module.url(forResource: "gpx", withExtension: "xsd", subdirectory: "Schemas")!
    }

    static func validate(_ data: Data) throws {
        // Point the schema location to the local copy so validation works offline.
        guard var text = String(data: data, encoding: .utf8) else {
            throw Failure(description: "not UTF-8")
        }
        text = text.replacingOccurrences(of: GPXWriter.schemaLocation, with: schemaURL.absoluteString)
        let document = try XMLDocument(xmlString: text, options: [])
        do {
            try document.validate()
        } catch {
            throw Failure(description: "GPX does not validate: \(error)")
        }
    }
}
#endif
