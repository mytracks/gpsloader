import Compression
import Foundation
@testable import GPSLoggerKit

/// A small ZIP writer for tests (design D8), following PKWARE's `APPNOTE.TXT`: local headers,
/// central directory and end of central directory, "stored" or "deflate", plus deliberate damage.
struct KMZTestFile {
    struct Entry {
        var name: String
        var data: [UInt8]
        /// 0 = stored, 8 = deflate; any other value stores the data under that method number.
        var method: UInt16 = 8
        var encrypted = false
        /// Sizes and CRC in a data descriptor after the data (flag bit 3).
        var dataDescriptor = false
        var wrongCRC = false
        /// Overrides the declared uncompressed size.
        var declaredSize: UInt32?
        /// Writes the ZIP64 marker 0xFFFFFFFF as sizes in the central directory.
        var zip64Sizes = false

        init(_ name: String, _ text: String, method: UInt16 = 8) {
            self.name = name
            self.data = Array(text.utf8)
            self.method = method
        }

        init(_ name: String, bytes: [UInt8], method: UInt16 = 8) {
            self.name = name
            self.data = bytes
            self.method = method
        }
    }

    var entries: [Entry] = []

    /// Raw DEFLATE via `Compression`.
    static func deflate(_ data: [UInt8]) -> [UInt8] {
        let capacity = data.count + 1024
        var output = [UInt8](repeating: 0, count: capacity)
        let size = data.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                compression_encode_buffer(destination.baseAddress!, capacity, source.baseAddress!, data.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        precondition(size > 0, "deflate failed")
        return Array(output.prefix(size))
    }

    func bytes() -> [UInt8] {
        var out: [UInt8] = []
        var central: [UInt8] = []
        for entry in entries {
            let crc = entry.data.withUnsafeBytes { CRC32.checksum($0) } ^ (entry.wrongCRC ? 0xFFFF : 0)
            let payload = entry.method == 8 ? Self.deflate(entry.data) : entry.data
            let size = entry.declaredSize ?? UInt32(entry.data.count)
            var flags: UInt16 = entry.encrypted ? 0x0001 : 0
            if entry.dataDescriptor { flags |= 0x0008 }
            let name = Array(entry.name.utf8)
            let offset = UInt32(out.count)

            out += le32(0x0403_4B50) + le16(20) + le16(flags) + le16(entry.method) + le16(0) + le16(0x21)
            if entry.dataDescriptor {
                out += le32(0) + le32(0) + le32(0)
            } else {
                out += le32(crc) + le32(UInt32(payload.count)) + le32(size)
            }
            out += le16(UInt16(name.count)) + le16(0) + name + payload
            if entry.dataDescriptor {
                out += le32(0x0807_4B50) + le32(crc) + le32(UInt32(payload.count)) + le32(size)
            }

            let compressed = entry.zip64Sizes ? 0xFFFF_FFFF : UInt32(payload.count)
            let uncompressed = entry.zip64Sizes ? 0xFFFF_FFFF : size
            central += le32(0x0201_4B50) + le16(20) + le16(20) + le16(flags) + le16(entry.method) + le16(0) + le16(0x21)
            central += le32(crc) + le32(compressed) + le32(uncompressed)
            central += le16(UInt16(name.count)) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(offset) + name
        }
        let centralOffset = UInt32(out.count)
        out += central
        out += le32(0x0605_4B50) + le16(0) + le16(0) + le16(UInt16(entries.count)) + le16(UInt16(entries.count))
        out += le32(UInt32(central.count)) + le32(centralOffset) + le16(0)
        return out
    }

    private func le16(_ value: UInt16) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8)] }
    private func le32(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8((value >> (8 * $0)) & 0xFF) } }
}
