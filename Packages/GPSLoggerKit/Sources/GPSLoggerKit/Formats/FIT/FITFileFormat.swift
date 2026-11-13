import Foundation

/// Garmin FIT files (spec `fit-import`), decoded according to the public FIT protocol description
/// and the FIT profile (message and field numbers, scale, offset). See PROVENANCE.md.
///
/// Every file becomes one track: `record` messages are its points, timer stops split it into
/// segments, the `course` name (if any) names it, and `course_point` messages become waypoints.
public struct FITFileFormat: FileFormat {
    public init() {}

    public var id: FileFormatID { .fit }
    public var displayName: String { LocalizedStrings.string("format.fit") }
    public var fileExtensions: [String] { ["fit"] }

    /// Header size byte 12 or 14 and the data type `.FIT` at bytes 8–11.
    public func matches(prefix: Data) -> Bool {
        let bytes = [UInt8](prefix.prefix(12))
        guard bytes.count == 12, bytes[0] == 12 || bytes[0] == 14 else { return false }
        return Array(bytes[8..<12]) == FITDecoder.signature
    }

    public func read(_ inputs: [FileInput]) throws -> ImportResult {
        var recording = Recording()
        var warnings: [ImportWarning] = []
        for input in inputs {
            let file = try input.data.withUnsafeBytes { raw in
                var decoder = FITDecoder(bytes: raw, fileName: input.name)
                try decoder.decode()
                return decoder.result
            }
            let track = Track(name: file.courseName ?? baseName(ofFile: input.name), segments: file.segments)
            if track.pointCount > 0 { recording.tracks.append(track) }
            recording.waypoints += file.waypoints
            warnings += file.warnings
        }
        return ImportResult(recording: recording, warnings: warnings)
    }
}

/// What one FIT file yielded.
struct FITFileContent {
    var segments: [TrackSegment] = []
    var waypoints: [Waypoint] = []
    var courseName: String?
    var warnings: [ImportWarning] = []
}

/// FIT checksum: CRC-16 with the reflected polynomial 0xA001 and initial value 0 (CRC-16/ARC),
/// as described in the FIT protocol.
enum FITCRC {
    private static let table: [UInt16] = (0..<16).map { nibble in
        var crc = UInt16(nibble)
        for _ in 0..<4 { crc = crc & 1 != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1 }
        return crc
    }

    static func update(_ crc: UInt16, _ byte: UInt8) -> UInt16 {
        var crc = crc
        crc = (crc >> 4) ^ table[Int((crc ^ UInt16(byte)) & 0xF)]
        crc = (crc >> 4) ^ table[Int((crc ^ UInt16(byte >> 4)) & 0xF)]
        return crc
    }

    static func checksum(_ bytes: some Sequence<UInt8>) -> UInt16 {
        bytes.reduce(0, update)
    }
}

/// Decodes one input (possibly several chained FIT files) from a raw buffer that is only valid
/// during the enclosing `withUnsafeBytes` call.
struct FITDecoder {
    static let signature: [UInt8] = Array(".FIT".utf8)
    /// Seconds between the Unix epoch and the FIT epoch (1989-12-31T00:00:00Z).
    static let epochOffset: TimeInterval = 631_065_600
    /// Timestamps below this value are relative device time, not UTC.
    static let minimumAbsoluteTime: UInt32 = 0x1000_0000

    /// Global message numbers and field numbers from the FIT profile.
    enum Message {
        static let record: UInt16 = 20
        static let event: UInt16 = 21
        static let course: UInt16 = 31
        static let coursePoint: UInt16 = 32
    }
    static let timestampField: UInt8 = 253

    private struct FieldDefinition {
        var number: UInt8
        var offset: Int
        var size: Int
        var baseType: UInt8
    }

    private struct Definition {
        var global: UInt16
        var bigEndian: Bool
        var fields: [FieldDefinition]
        /// Size of a data message body (fields plus developer fields).
        var size: Int
    }

    private let bytes: UnsafeRawBufferPointer
    private let fileName: String
    private var warnings: WarningCollector
    private var cancellation = CancellationCheck()
    private var content = FITFileContent()
    private var segment: [TrackPoint] = []
    private var messageNumber = 0

    init(bytes: UnsafeRawBufferPointer, fileName: String) {
        self.bytes = bytes
        self.fileName = fileName
        self.warnings = WarningCollector(fileName: fileName)
    }

    var result: FITFileContent {
        var content = content
        if !segment.isEmpty { content.segments.append(TrackSegment(points: segment)) }
        content.warnings = warnings.warnings
        return content
    }

    // MARK: - Files and header

    /// Decodes all chained FIT files. Throws for an invalid first header and on cancellation.
    mutating func decode() throws {
        var offset = 0
        var isFirst = true
        while bytes.count - offset >= 12 || isFirst {
            guard let headerSize = validHeaderSize(at: offset) else {
                if isFirst {
                    throw GPSLoggerError(.malformed(line: nil), fileName: fileName,
                                         detail: "invalid FIT file header at byte \(offset)")
                }
                return  // trailing bytes that are no FIT file
            }
            isFirst = false
            guard let next = try decodeFile(at: offset, headerSize: headerSize) else { return }
            offset = next
        }
    }

    private func validHeaderSize(at offset: Int) -> Int? {
        guard bytes.count - offset >= 12 else { return nil }
        let size = Int(bytes[offset])
        guard size == 12 || size == 14, bytes.count - offset >= size else { return nil }
        for i in 0..<4 where bytes[offset + 8 + i] != Self.signature[i] { return nil }
        return size
    }

    /// Decodes one FIT file. Returns the offset after its CRC, or `nil` when decoding had to stop.
    private mutating func decodeFile(at start: Int, headerSize: Int) throws -> Int? {
        if headerSize == 14 {
            let stored = UInt16(bytes[start + 12]) | UInt16(bytes[start + 13]) << 8
            if stored != 0, stored != FITCRC.checksum(bytes[start..<(start + 12)]) {
                warnings.add(.fileChecksumMismatch, line: nil)
            }
        }
        let dataSize = Int(readUInt(at: start + 4, size: 4, bigEndian: false))
        let dataStart = start + headerSize
        let dataEnd = dataStart + dataSize
        let end = min(dataEnd, bytes.count)
        guard try decodeMessages(from: dataStart, to: end) else { return nil }
        guard dataEnd <= bytes.count, dataEnd + 2 <= bytes.count else {
            warnings.add(.truncatedFile, line: nil)
            return nil
        }
        let stored = UInt16(bytes[dataEnd]) | UInt16(bytes[dataEnd + 1]) << 8
        if stored != FITCRC.checksum(bytes[start..<dataEnd]) {
            warnings.add(.fileChecksumMismatch, line: nil)
        }
        return dataEnd + 2
    }

    // MARK: - Messages

    /// Decodes the records of one data area. Returns `false` when it stopped at a damaged place.
    private mutating func decodeMessages(from start: Int, to end: Int) throws -> Bool {
        var definitions = [Definition?](repeating: nil, count: 16)
        var lastTimestamp: UInt32?
        var position = start
        while position < end {
            try cancellation.tick()
            messageNumber += 1
            let header = bytes[position]
            position += 1
            let local: Int
            var compressedTime: UInt32?
            if header & 0x80 != 0 {
                local = Int((header >> 5) & 0x03)
                let offset = UInt32(header & 0x1F)
                if let last = lastTimestamp {
                    var time = (last & ~0x1F) + offset
                    if offset < last & 0x1F { time += 0x20 }
                    compressedTime = time
                    lastTimestamp = time
                }
            } else if header & 0x40 != 0 {
                guard let (definition, next) = readDefinition(at: position, end: end,
                                                               hasDeveloperFields: header & 0x20 != 0) else {
                    warnings.add(.truncatedFile, line: nil)
                    return false
                }
                definitions[Int(header & 0x0F)] = definition
                position = next
                continue
            } else {
                local = Int(header & 0x0F)
            }
            guard let definition = definitions[local] else {
                warnings.add(.malformedRecord, line: messageNumber)
                return false
            }
            guard position + definition.size <= end else {
                warnings.add(.truncatedFile, line: nil)
                return false
            }
            let message = MessageView(bytes: bytes, start: position, definition: definition)
            if let time = message.unsigned(Self.timestampField) {
                lastTimestamp = UInt32(truncatingIfNeeded: time)
            }
            handle(message, compressedTime: compressedTime)
            position += definition.size
        }
        return true
    }

    private func readDefinition(at start: Int, end: Int, hasDeveloperFields: Bool) -> (Definition, Int)? {
        guard start + 5 <= end else { return nil }
        let bigEndian = bytes[start + 1] == 1
        let global = UInt16(truncatingIfNeeded: readUInt(at: start + 2, size: 2, bigEndian: bigEndian))
        let count = Int(bytes[start + 4])
        var position = start + 5
        guard position + count * 3 <= end else { return nil }
        var fields: [FieldDefinition] = []
        var size = 0
        for _ in 0..<count {
            let field = FieldDefinition(number: bytes[position], offset: size, size: Int(bytes[position + 1]),
                                        baseType: bytes[position + 2])
            fields.append(field)
            size += field.size
            position += 3
        }
        if hasDeveloperFields {
            guard position + 1 <= end else { return nil }
            let developerCount = Int(bytes[position])
            position += 1
            guard position + developerCount * 3 <= end else { return nil }
            for _ in 0..<developerCount {
                size += Int(bytes[position + 1])
                position += 3
            }
        }
        return (Definition(global: global, bigEndian: bigEndian, fields: fields, size: size), position)
    }

    private mutating func handle(_ message: MessageView, compressedTime: UInt32?) {
        switch message.definition.global {
        case Message.record:
            let time = message.unsigned(Self.timestampField).map { UInt32(truncatingIfNeeded: $0) } ?? compressedTime
            guard let latitude = message.signed(0), let longitude = message.signed(1) else { return }
            guard let position = Self.position(latitude, longitude) else {
                warnings.add(.invalidCoordinate, line: messageNumber)
                return
            }
            let altitude = message.unsigned(78) ?? message.unsigned(2)
            let speed = message.unsigned(73) ?? message.unsigned(6)
            var quality = PositionQuality()
            quality.speed = speed.map { Double($0) / 1000 }
            if time == nil { warnings.add(.missingDate, line: messageNumber) }
            segment.append(TrackPoint(latitude: position.latitude, longitude: position.longitude,
                                      elevation: altitude.map { Double($0) / 5 - 500 },
                                      time: date(time), quality: quality))
        case Message.event:
            // event "timer" (0) with event_type "stop" (1) or "stop_all" (4) ends the segment.
            if message.unsigned(0) == 0, let type = message.unsigned(1), type == 1 || type == 4, !segment.isEmpty {
                content.segments.append(TrackSegment(points: segment))
                segment = []
            }
        case Message.course:
            if content.courseName == nil, let name = message.string(5), !name.isEmpty {
                content.courseName = name
            }
        case Message.coursePoint:
            guard let latitude = message.signed(2), let longitude = message.signed(3) else { return }
            guard let position = Self.position(latitude, longitude) else {
                warnings.add(.invalidCoordinate, line: messageNumber)
                return
            }
            let name = message.string(6).flatMap { $0.isEmpty ? nil : $0 }
            content.waypoints.append(Waypoint(latitude: position.latitude, longitude: position.longitude,
                                              time: date(message.unsigned(1).map { UInt32(truncatingIfNeeded: $0) }),
                                              name: name))
        default:
            break
        }
    }

    /// Semicircles to degrees; `nil` outside the valid range.
    static func position(_ latitude: Int64, _ longitude: Int64) -> (latitude: Double, longitude: Double)? {
        let factor = 180.0 / 2_147_483_648.0
        let lat = Double(latitude) * factor
        let lon = Double(longitude) * factor
        guard (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return (lat, lon)
    }

    private mutating func date(_ time: UInt32?) -> Date? {
        guard let time else { return nil }
        guard time >= Self.minimumAbsoluteTime else {
            warnings.add(.missingDate, line: messageNumber)
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(time) + Self.epochOffset)
    }

    // MARK: - Fields

    private func readUInt(at offset: Int, size: Int, bigEndian: Bool) -> UInt64 {
        Self.readUInt(bytes, at: offset, size: size, bigEndian: bigEndian)
    }

    fileprivate static func readUInt(_ bytes: UnsafeRawBufferPointer, at offset: Int, size: Int, bigEndian: Bool) -> UInt64 {
        var value: UInt64 = 0
        for i in 0..<size {
            let byte = UInt64(bytes[offset + (bigEndian ? i : size - 1 - i)])
            value = value << 8 | byte
        }
        return value
    }

    /// Access to the fields of one data message.
    private struct MessageView {
        let bytes: UnsafeRawBufferPointer
        let start: Int
        let definition: Definition

        /// Base type number (low 5 bits) → (size, signed, invalid value).
        private static func baseType(_ type: UInt8) -> (size: Int, signed: Bool, invalid: UInt64)? {
            switch type & 0x1F {
            case 0, 2, 13: (1, false, 0xFF)          // enum, uint8, byte
            case 1: (1, true, 0x7F)                  // sint8
            case 3: (2, true, 0x7FFF)                // sint16
            case 4: (2, false, 0xFFFF)               // uint16
            case 5: (4, true, 0x7FFF_FFFF)           // sint32
            case 6: (4, false, 0xFFFF_FFFF)          // uint32
            case 10: (1, false, 0)                   // uint8z
            case 11: (2, false, 0)                   // uint16z
            case 12: (4, false, 0)                   // uint32z
            case 14: (8, true, 0x7FFF_FFFF_FFFF_FFFF) // sint64
            case 15: (8, false, 0xFFFF_FFFF_FFFF_FFFF) // uint64
            case 16: (8, false, 0)                   // uint64z
            default: nil                             // string, float32, float64
            }
        }

        private func raw(_ number: UInt8) -> (value: UInt64, size: Int, signed: Bool)? {
            guard let field = definition.fields.first(where: { $0.number == number }),
                  let type = Self.baseType(field.baseType), field.size == type.size else { return nil }
            let value = FITDecoder.readUInt(bytes, at: start + field.offset, size: field.size, bigEndian: definition.bigEndian)
            guard value != type.invalid else { return nil }
            return (value, field.size, type.signed)
        }

        /// An integer field as unsigned value, `nil` if absent or invalid.
        func unsigned(_ number: UInt8) -> UInt64? {
            guard let field = raw(number), !field.signed else { return nil }
            return field.value
        }

        /// An integer field as signed value (sign-extended), `nil` if absent or invalid.
        func signed(_ number: UInt8) -> Int64? {
            guard let field = raw(number) else { return nil }
            guard field.signed else { return Int64(clamping: field.value) }
            let shift = UInt64(64 - field.size * 8)
            return Int64(bitPattern: field.value << shift) >> Int64(shift)
        }

        /// A string field (UTF-8 up to the first NUL), `nil` if absent.
        func string(_ number: UInt8) -> String? {
            guard let field = definition.fields.first(where: { $0.number == number }), field.baseType & 0x1F == 7 else {
                return nil
            }
            var utf8: [UInt8] = []
            for i in 0..<field.size {
                let byte = bytes[start + field.offset + i]
                if byte == 0 { break }
                utf8.append(byte)
            }
            return utf8.isEmpty ? nil : String(decoding: utf8, as: UTF8.self)
        }
    }
}
