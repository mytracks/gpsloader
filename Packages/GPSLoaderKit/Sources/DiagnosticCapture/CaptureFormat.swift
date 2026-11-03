import Foundation
import LoggerCore

/// One line of a capture file (JSON Lines, spec `diagnostic-capture`).
///
/// The first line is the header (`kind == "header"`), every further line is an entry.
/// Unknown fields are ignored when reading, so the format can grow compatibly; incompatible
/// changes increase `CaptureFormat.version`.
public struct CaptureLine: Codable, Sendable, Equatable {
    // Header fields
    public var format: String?
    public var version: Int?
    public var created: String?
    public var app: String?
    public var os: String?
    public var arch: String?
    public var translated: Bool?
    public var driver: String?
    public var port: String?
    public var params: [String: String]?

    // Entry fields
    /// "header", "tx", "rx", "event" or "process".
    public var kind: String
    /// Milliseconds since the start of the capture.
    public var t: Int?
    public var source: String?
    public var hex: String?
    public var ascii: String?
    public var name: String?
    public var detail: String?
    public var executable: String?
    public var arguments: [String]?
    public var stdout: String?
    public var stderr: String?
    public var exit: Int32?
    public var duration: Double?

    public init(kind: String) {
        self.kind = kind
    }

    /// The raw bytes of a `tx`/`rx` line.
    public var bytes: [UInt8]? {
        hex.flatMap { [UInt8](hexString: $0) }
    }
}

public enum CaptureFormat {
    public static let identifier = "gpsloader-capture"
    public static let version = 1
    public static let fileExtension = "jsonl"

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case empty
        case notACapture
        case unsupportedVersion(Int)
        case invalidLine(Int)

        public var description: String {
            switch self {
            case .empty: "The capture is empty."
            case .notACapture: "The file is not a gpsloader capture."
            case let .unsupportedVersion(version): "Unsupported capture version \(version)."
            case let .invalidLine(line): "Line \(line) is not valid JSON."
            }
        }
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// Encodes lines as JSON Lines.
    public static func encode(_ lines: [CaptureLine]) -> Data {
        let encoder = encoder()
        var data = Data()
        for line in lines {
            // Encoding these plain value types cannot fail.
            data.append(try! encoder.encode(line))
            data.append(0x0A)
        }
        return data
    }

    /// Parses a capture. Returns the header and the entries.
    public static func decode(_ data: Data) throws -> (header: CaptureLine, entries: [CaptureLine]) {
        let decoder = JSONDecoder()
        var lines: [CaptureLine] = []
        for (index, raw) in data.split(separator: 0x0A, omittingEmptySubsequences: true).enumerated() {
            do {
                lines.append(try decoder.decode(CaptureLine.self, from: Data(raw)))
            } catch {
                throw ParseError.invalidLine(index + 1)
            }
        }
        guard let header = lines.first else { throw ParseError.empty }
        guard header.kind == "header", header.format == identifier else { throw ParseError.notACapture }
        guard header.version == version else { throw ParseError.unsupportedVersion(header.version ?? 0) }
        return (header, Array(lines.dropFirst()))
    }
}
