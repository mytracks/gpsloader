import Foundation

/// Byte-based line splitting for text formats (NMEA, IGC).
enum TextLines {
    /// Splits data into lines (LF, CR or CRLF) whose first byte satisfies `filter`.
    /// Bytes are decoded as UTF-8 with replacement.
    static func lines(of data: Data, where filter: (UInt8) -> Bool) -> [(number: Int, text: Substring)] {
        var result: [(Int, Substring)] = []
        forEachLine(in: data, where: filter) { number, text in
            result.append((number, text))
            return true
        }
        return result
    }

    /// Calls `body` with the 1-based line number and text of every non-empty line whose first byte
    /// satisfies `filter`. Other lines are skipped without decoding. `body` returns `false` to stop.
    /// A CRLF pair counts as one line break.
    static func forEachLine(in data: Data, where filter: (UInt8) -> Bool,
                            _ body: (Int, Substring) throws -> Bool) rethrows {
        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            let bytes = buffer.bindMemory(to: UInt8.self)
            var lineNumber = 0
            var start = 0
            var i = 0
            let count = bytes.count
            while start < count {
                i = start
                while i < count, bytes[i] != 0x0A, bytes[i] != 0x0D { i += 1 }
                lineNumber += 1
                if i > start, filter(bytes[start]) {
                    let text = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<i]), as: UTF8.self)
                    if try !body(lineNumber, Substring(text)) { return }
                }
                // Skip the terminator; CRLF counts as one line break.
                if i < count, bytes[i] == 0x0D, i + 1 < count, bytes[i + 1] == 0x0A {
                    start = i + 2
                } else {
                    start = i + 1
                }
            }
        }
    }
}
