import Compression
import Foundation

/// CRC-32 (ISO 3309, reflected polynomial 0xEDB88320) as used by ZIP.
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = value & 1 == 1 ? (value >> 1) ^ 0xEDB8_8320 : value >> 1
        }
        return value
    }

    static func checksum(_ bytes: UnsafeRawBufferPointer, initial: UInt32 = 0) -> UInt32 {
        var crc = ~initial
        for byte in bytes {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return ~crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { checksum($0) }
    }
}

/// Reads the main KML document of a KMZ (ZIP) archive (design D3), following PKWARE's public
/// `APPNOTE.TXT`: end of central directory, central directory, local header; methods "stored" and
/// "deflate". ZIP64, encryption and other methods are rejected.
enum KMZArchive {
    /// Largest accepted uncompressed document size.
    static let maximumDocumentSize = 1 << 30
    /// Output block size while inflating; cancellation is checked after every block.
    static let blockSize = 64 * 1024

    private static let localHeaderSignature: UInt32 = 0x0403_4B50
    private static let centralHeaderSignature: UInt32 = 0x0201_4B50
    private static let endSignature: UInt32 = 0x0605_4B50
    private static let zip64LocatorSignature: UInt32 = 0x0706_4B50

    struct Entry: Equatable {
        var name: String
        var flags: UInt16
        var method: UInt16
        var crc: UInt32
        var compressedSize: UInt32
        var uncompressedSize: UInt32
        var localHeaderOffset: UInt32
    }

    /// Whether the data starts with a ZIP local file header.
    static func isZIP(_ data: Data) -> Bool {
        data.count >= 4 && data.prefix(4).elementsEqual([0x50, 0x4B, 0x03, 0x04])
    }

    /// Name of the first entry, read from the first local header in `prefix`.
    static func firstEntryName(in prefix: Data) -> String? {
        let bytes = [UInt8](prefix.prefix(30 + 0xFFFF))
        guard bytes.count >= 30, isZIP(prefix) else { return nil }
        let length = Int(bytes[26]) | Int(bytes[27]) << 8
        guard bytes.count >= 30 + length else { return nil }
        return String(decoding: bytes[30..<(30 + length)], as: UTF8.self)
    }

    /// The uncompressed main document (`doc.kml` in the root, else the first `.kml` in the root).
    /// A wrong CRC-32 adds a `fileChecksumMismatch` warning.
    /// - Throws: `GPSLoggerError` or `CancellationError`.
    static func document(in data: Data, fileName: String, warnings: inout WarningCollector) throws -> Data {
        try data.withUnsafeBytes { raw in
            func fail(_ kind: GPSLoggerErrorKind, _ detail: String) -> GPSLoggerError {
                GPSLoggerError(kind, fileName: fileName, detail: detail)
            }
            let truncated = fail(.malformed(line: nil), "truncated or invalid ZIP archive")
            let entries = try centralDirectory(raw, truncated: truncated, fail: fail)
            guard let entry = mainDocument(in: entries) else {
                throw fail(.noUsableData, "no KML document in archive")
            }
            if entry.flags & 0x0001 != 0 {
                throw fail(.unreadable, "encrypted ZIP entry \(entry.name)")
            }
            if entry.compressedSize == 0xFFFF_FFFF || entry.uncompressedSize == 0xFFFF_FFFF
                || entry.localHeaderOffset == 0xFFFF_FFFF {
                throw fail(.unreadable, "ZIP64 archives are not supported")
            }
            guard entry.method == 0 || entry.method == 8 else {
                throw fail(.unreadable, "unsupported ZIP compression method \(entry.method)")
            }
            guard Int(entry.uncompressedSize) <= maximumDocumentSize else {
                throw fail(.unreadable, "\(entry.name) is larger than 1 GiB")
            }

            let offset = Int(entry.localHeaderOffset)
            guard offset + 30 <= raw.count, read32(raw, offset) == localHeaderSignature else { throw truncated }
            let start = offset + 30 + Int(read16(raw, offset + 26)) + Int(read16(raw, offset + 28))
            let end = start + Int(entry.compressedSize)
            guard end <= raw.count else { throw truncated }
            let source = UnsafeRawBufferPointer(rebasing: raw[start..<end])

            let document: Data
            if entry.method == 0 {
                guard entry.compressedSize == entry.uncompressedSize else {
                    throw fail(.malformed(line: nil), "stored ZIP entry with inconsistent sizes")
                }
                document = Data(source)
            } else {
                document = try inflate(source, expectedSize: Int(entry.uncompressedSize), fail: fail)
            }
            if CRC32.checksum(document) != entry.crc {
                warnings.add(.fileChecksumMismatch, line: nil)
            }
            return document
        }
    }

    /// `doc.kml` in the root, else the first entry in the root ending in `.kml`.
    static func mainDocument(in entries: [Entry]) -> Entry? {
        let rootDocuments = entries.filter { !$0.name.contains("/") && $0.name.lowercased().hasSuffix(".kml") }
        return rootDocuments.first { $0.name.lowercased() == "doc.kml" } ?? rootDocuments.first
    }

    // MARK: - Structure

    private static func centralDirectory(_ raw: UnsafeRawBufferPointer, truncated: GPSLoggerError,
                                         fail: (GPSLoggerErrorKind, String) -> GPSLoggerError) throws -> [Entry] {
        guard raw.count >= 22 else { throw truncated }
        var position = raw.count - 22
        let lowest = max(0, raw.count - 22 - 0xFFFF)
        while position >= lowest, read32(raw, position) != endSignature {
            position -= 1
        }
        guard position >= lowest else { throw truncated }
        let end = position
        if end >= 20, read32(raw, end - 20) == zip64LocatorSignature {
            throw fail(.unreadable, "ZIP64 archives are not supported")
        }
        let count = Int(read16(raw, end + 10))
        let size = read32(raw, end + 12)
        let offset = read32(raw, end + 16)
        if count == 0xFFFF || size == 0xFFFF_FFFF || offset == 0xFFFF_FFFF {
            throw fail(.unreadable, "ZIP64 archives are not supported")
        }
        guard read16(raw, end + 4) == 0, read16(raw, end + 6) == 0 else {
            throw fail(.unreadable, "multi-part ZIP archives are not supported")
        }
        guard Int(offset) + Int(size) <= end else { throw truncated }

        var entries: [Entry] = []
        var p = Int(offset)
        for _ in 0..<count {
            guard p + 46 <= end, read32(raw, p) == centralHeaderSignature else { throw truncated }
            let nameLength = Int(read16(raw, p + 28))
            let extraLength = Int(read16(raw, p + 30))
            let commentLength = Int(read16(raw, p + 32))
            guard p + 46 + nameLength <= end else { throw truncated }
            let name = String(decoding: UnsafeRawBufferPointer(rebasing: raw[(p + 46)..<(p + 46 + nameLength)]),
                              as: UTF8.self)
            entries.append(Entry(name: name, flags: read16(raw, p + 8), method: read16(raw, p + 10),
                                 crc: read32(raw, p + 16), compressedSize: read32(raw, p + 20),
                                 uncompressedSize: read32(raw, p + 24), localHeaderOffset: read32(raw, p + 42)))
            p += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// Raw DEFLATE (RFC 1951) via `Compression` (`COMPRESSION_ZLIB` has no zlib header).
    private static func inflate(_ source: UnsafeRawBufferPointer, expectedSize: Int,
                                fail: (GPSLoggerErrorKind, String) -> GPSLoggerError) throws -> Data {
        let damaged = fail(.malformed(line: nil), "deflate data is damaged or truncated")
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw damaged
        }
        defer { compression_stream_destroy(stream) }

        let block = UnsafeMutablePointer<UInt8>.allocate(capacity: blockSize)
        defer { block.deallocate() }
        var output = Data()
        output.reserveCapacity(expectedSize)
        guard let base = source.baseAddress, !source.isEmpty else { throw damaged }
        stream.pointee.src_ptr = base.assumingMemoryBound(to: UInt8.self)
        stream.pointee.src_size = source.count
        let finalize = Int32(bitPattern: COMPRESSION_STREAM_FINALIZE.rawValue)
        var idleRounds = 0
        while true {
            stream.pointee.dst_ptr = block
            stream.pointee.dst_size = blockSize
            let status = compression_stream_process(stream, finalize)
            let produced = blockSize - stream.pointee.dst_size
            if produced > 0 {
                guard output.count + produced <= expectedSize else {
                    throw fail(.malformed(line: nil), "ZIP entry is larger than declared")
                }
                output.append(block, count: produced)
            }
            try Task.checkCancellation()
            switch status {
            case COMPRESSION_STATUS_END:
                guard output.count == expectedSize else {
                    throw fail(.malformed(line: nil), "ZIP entry is smaller than declared")
                }
                return output
            case COMPRESSION_STATUS_OK:
                // Input used up without reaching the end of the stream: truncated.
                idleRounds = produced == 0 && stream.pointee.src_size == 0 ? idleRounds + 1 : 0
                if idleRounds > 1 { throw damaged }
            default:
                throw damaged
            }
        }
    }

    private static func read16(_ raw: UnsafeRawBufferPointer, _ offset: Int) -> UInt16 {
        UInt16(raw[offset]) | UInt16(raw[offset + 1]) << 8
    }

    private static func read32(_ raw: UnsafeRawBufferPointer, _ offset: Int) -> UInt32 {
        UInt32(raw[offset]) | UInt32(raw[offset + 1]) << 8 | UInt32(raw[offset + 2]) << 16 | UInt32(raw[offset + 3]) << 24
    }
}
