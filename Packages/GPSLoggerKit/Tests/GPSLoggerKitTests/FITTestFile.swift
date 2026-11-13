import Foundation
@testable import GPSLoggerKit

/// A small FIT encoder for tests (design D8): header, definitions (LE/BE, developer fields),
/// data messages, compressed timestamp headers and CRC, following the FIT protocol.
struct FITTestFile {
    /// Base type bytes of the FIT protocol.
    enum BaseType: UInt8 {
        case enumeration = 0x00, uint8 = 0x02, string = 0x07, sint16 = 0x83, uint16 = 0x84, sint32 = 0x85, uint32 = 0x86
    }

    /// A field value in definition order.
    enum Value {
        case enumeration(UInt8), uint8(UInt8), uint16(UInt16), uint32(UInt32), sint32(Int32), string(String, size: Int)

        var baseType: BaseType {
            switch self {
            case .enumeration: .enumeration
            case .uint8: .uint8
            case .uint16: .uint16
            case .uint32: .uint32
            case .sint32: .sint32
            case .string: .string
            }
        }

        var size: Int {
            switch self {
            case .enumeration, .uint8: 1
            case .uint16: 2
            case .uint32, .sint32: 4
            case .string(_, let size): size
            }
        }

        func bytes(bigEndian: Bool) -> [UInt8] {
            func integer(_ value: UInt64, _ size: Int) -> [UInt8] {
                let little = (0..<size).map { UInt8(truncatingIfNeeded: value >> (8 * UInt64($0))) }
                return bigEndian ? little.reversed() : little
            }
            switch self {
            case .enumeration(let v), .uint8(let v): return [v]
            case .uint16(let v): return integer(UInt64(v), 2)
            case .uint32(let v): return integer(UInt64(v), 4)
            case .sint32(let v): return integer(UInt64(UInt32(bitPattern: v)), 4)
            case .string(let text, let size):
                var utf8 = Array(text.utf8.prefix(size - 1))
                utf8 += [UInt8](repeating: 0, count: size - utf8.count)
                return utf8
            }
        }
    }

    /// Global message numbers used in tests.
    static let record: UInt16 = 20, event: UInt16 = 21, course: UInt16 = 31, coursePoint: UInt16 = 32, fileID: UInt16 = 0

    var headerSize = 14
    private(set) var body: [UInt8] = []
    private var bigEndian: [UInt8: Bool] = [:]

    /// Writes a definition message. `values` only provide field numbers, types and sizes.
    mutating func define(local: UInt8, global: UInt16, fields: [(UInt8, Value)],
                         developerFieldSizes: [UInt8] = [], bigEndian: Bool = false) {
        body.append(0x40 | (developerFieldSizes.isEmpty ? 0 : 0x20) | local)
        body.append(0)
        body.append(bigEndian ? 1 : 0)
        body += Value.uint16(global).bytes(bigEndian: bigEndian)
        body.append(UInt8(fields.count))
        for (number, value) in fields {
            body += [number, UInt8(value.size), value.baseType.rawValue]
        }
        if !developerFieldSizes.isEmpty {
            body.append(UInt8(developerFieldSizes.count))
            for (index, size) in developerFieldSizes.enumerated() {
                body += [UInt8(index), size, 0]
            }
        }
        self.bigEndian[local] = bigEndian
    }

    /// Writes a data message with a normal header, or with a compressed timestamp header (local 0–3).
    mutating func write(local: UInt8, _ values: [Value], developerBytes: [UInt8] = [], compressedTime: UInt8? = nil) {
        if let compressedTime {
            body.append(0x80 | (local & 0x03) << 5 | (compressedTime & 0x1F))
        } else {
            body.append(local & 0x0F)
        }
        let bigEndian = self.bigEndian[local] ?? false
        for value in values { body += value.bytes(bigEndian: bigEndian) }
        body += developerBytes
    }

    /// Appends raw bytes to the data area, e.g. a header of an undefined local message type.
    mutating func appendRaw(_ bytes: [UInt8]) {
        body += bytes
    }

    /// Repeats the last `messageSize` bytes of the data area until it holds `count` copies of that message.
    /// Doubles the bytes instead of encoding every message, so large test files are cheap to build.
    mutating func repeatLastMessage(size messageSize: Int, count: Int) {
        let message = Array(body.suffix(messageSize))
        var block = message
        while block.count * 2 <= messageSize * (count - 1) { block += block }
        var remaining = count - 1
        while remaining > 0 {
            let copies = min(remaining, block.count / messageSize)
            body += block.prefix(copies * messageSize)
            remaining -= copies
        }
    }

    /// The complete file: header (with header CRC for 14 bytes), data and file CRC.
    /// Without `checksum` the file CRC is 0 (cheaper for large files; the decoder then warns).
    func bytes(headerSizeByte: UInt8? = nil, checksum: Bool = true) -> [UInt8] {
        var header: [UInt8] = [headerSizeByte ?? UInt8(headerSize), 0x20]
        header += Value.uint16(21_218).bytes(bigEndian: false)
        header += Value.uint32(UInt32(body.count)).bytes(bigEndian: false)
        header += Array(".FIT".utf8)
        if headerSize == 14 {
            header += Value.uint16(FITCRC.checksum(header)).bytes(bigEndian: false)
        }
        let file = header + body
        return file + Value.uint16(checksum ? FITCRC.checksum(file) : 0).bytes(bigEndian: false)
    }

    // MARK: - Common messages

    /// Record definition on local 0: timestamp, position, altitude, speed.
    static let recordFields: [(UInt8, Value)] = [
        (253, .uint32(0)), (0, .sint32(0)), (1, .sint32(0)), (2, .uint16(0)), (6, .uint16(0)),
    ]

    mutating func defineRecords(local: UInt8 = 0, bigEndian: Bool = false) {
        define(local: local, global: Self.record, fields: Self.recordFields, bigEndian: bigEndian)
    }

    /// A record with the fields of ``recordFields``; `nil` writes the invalid value.
    mutating func record(local: UInt8 = 0, time: UInt32, latitude: Int32, longitude: Int32,
                         altitude: UInt16? = nil, speed: UInt16? = nil) {
        write(local: local, [.uint32(time), .sint32(latitude), .sint32(longitude),
                             .uint16(altitude ?? 0xFFFF), .uint16(speed ?? 0xFFFF)])
    }

    /// Timer event definition on the given local type.
    mutating func defineEvents(local: UInt8 = 1) {
        define(local: local, global: Self.event, fields: [(253, .uint32(0)), (0, .enumeration(0)), (1, .enumeration(0))])
    }

    /// A timer event; type 0 = start, 1 = stop, 4 = stop_all.
    mutating func timer(local: UInt8 = 1, time: UInt32, type: UInt8) {
        write(local: local, [.uint32(time), .enumeration(0), .enumeration(type)])
    }

    /// Degrees to semicircles.
    static func semicircles(_ degrees: Double) -> Int32 {
        Int32((degrees * 2_147_483_648 / 180).rounded())
    }
}
