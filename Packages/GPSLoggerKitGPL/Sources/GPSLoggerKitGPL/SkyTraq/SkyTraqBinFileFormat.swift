// Ported from GPSBabel skytraq.cc (tag gpsbabel_1_7_0), file reader of the format skytraq-bin.
// Original: Copyright (C) 2008-2019 Mathias Adam; 2008 J.C Haessig; 2009-2010 Josef Reisinger.
// Licensed under the GNU General Public License, version 2 or (at your option) any later version.
// Translated to Swift and modified for gpsloader by Dirk Stichling, 2026-11-13.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GPSLoggerKit

extension FileFormatID {
    public static let skytraqBin: FileFormatID = "skytraq-bin"
}

/// Memory dumps of SkyTraq Venus 5/6 based loggers (spec `skytraq-import`), as written by gpsbabel's
/// `skytraq` driver with `dump-file=` or by vendor software.
///
/// Every dump becomes one track named after the file; POI entries also become waypoints.
public struct SkyTraqBinFileFormat: FileFormat {
    /// Time from which the GPS week cycle is chosen (the 1024 weeks up to this time).
    var reference: @Sendable () -> Date = { Date() }

    public init() {}

    init(reference: Date) {
        self.reference = { reference }
    }

    public var id: FileFormatID { .skytraqBin }
    public var displayName: String { L10n.string("format.skytraq-bin") }
    public var fileExtensions: [String] { ["bin"] }

    public func matches(prefix: Data) -> Bool {
        SkyTraqDump.looksLikeDump(ByteReader(prefix))
    }

    public func read(_ inputs: [FileInput]) throws -> ImportResult {
        var recording = Recording()
        var warnings: [ImportWarning] = []
        let reference = reference()
        for input in inputs {
            var dump = SkyTraqDump(fileName: input.name, reference: reference)
            try dump.read(ByteReader(input.data))
            if !dump.points.isEmpty {
                recording.tracks.append(Track(name: trackName(ofFile: input.name),
                                              segments: [TrackSegment(points: dump.points)]))
            }
            recording.waypoints += dump.waypoints
            warnings += dump.warnings.all
        }
        return ImportResult(recording: recording, warnings: warnings)
    }
}

/// Decoder of one dump (`file_read`, `process_data_sector` and `process_data_item` of the source).
struct SkyTraqDump {
    static let sectorSize = 4096
    static let fullLength = 18
    static let compactLength = 8
    static let multiHzLength = 20

    enum ItemType: UInt8 {
        case multiHz = 0x2, full = 0x4, poi = 0x6, compact = 0x8, multiHzPOI = 0xC

        var length: Int {
            switch self {
            case .multiHz, .multiHzPOI: SkyTraqDump.multiHzLength
            case .full, .poi: SkyTraqDump.fullLength
            case .compact: SkyTraqDump.compactLength
            }
        }
    }

    private(set) var points: [TrackPoint] = []
    private(set) var waypoints: [Waypoint] = []
    var warnings: Warnings
    private let reference: Date

    // State carried from item to item (`struct read_state`).
    private var week = 0
    private var secondOfWeek = 0.0
    private var x = 0, y = 0, z = 0
    private var hasPosition = false
    private var poiCount = 0

    init(fileName: String, reference: Date) {
        warnings = Warnings(fileName: fileName)
        self.reference = reference
    }

    /// - Parameter stopAtPartialSector: `true` for files (`file_read`: a sector ending more than 18 bytes early
    ///   ends the dump); `false` for a device download (`skytraq_read_tracks`: only an empty sector ends it).
    mutating func read(_ data: ByteReader, stopAtPartialSector: Bool = true) throws {
        var cancellation = Cancellation(interval: 1024)
        var sectorStart = 0
        sectors: while sectorStart < data.count {
            let sectorEnd = min(sectorStart + Self.sectorSize, data.count)
            var offset = sectorStart
            while offset < sectorEnd, let first = data.u8(offset), first != 0xFF {
                try cancellation.tick()
                guard let type = ItemType(rawValue: first >> 4), offset + type.length <= sectorEnd else {
                    warnings.add(.truncatedFile, at: nil)
                    break sectors
                }
                item(type, data, at: offset)
                offset += type.length
            }
            // A sector that ends well before its end is empty; the dump ends there.
            if stopAtPartialSector ? offset - sectorStart < Self.sectorSize - Self.fullLength : offset == sectorStart { break }
            sectorStart += Self.sectorSize
        }
    }

    /// "Middle endian" 32-bit value of the source (`me_read32`): two big endian halves, low half first.
    static func middleEndian32(_ data: ByteReader, _ offset: Int) -> UInt32 {
        guard let low = data.u16be(offset), let high = data.u16be(offset + 2) else { return 0 }
        return UInt32(high) << 16 | UInt32(low)
    }

    private mutating func item(_ type: ItemType, _ data: ByteReader, at offset: Int) {
        let byte0 = Int(data.u8(offset) ?? 0), byte1 = Int(data.u8(offset + 1) ?? 0)
        let speed = Double((byte0 & 0x0F) << 8 | byte1) / 3.6

        switch type {
        case .multiHz, .multiHzPOI:
            week = (byte0 & 0x03) << 8 | byte1
            let kmh = Double(data.u16be(offset + 2) ?? 0)
            let milliseconds = Self.middleEndian32(data, offset + 4) & 0x3FFF_FFFF
            secondOfWeek = Double(milliseconds) / 1000
            let latitude = Double(Int32(bitPattern: Self.middleEndian32(data, offset + 8))) / 1_048_576  // 2^20
            let longitude = Double(Int32(bitPattern: Self.middleEndian32(data, offset + 12))) / 1_048_576
            let altitude = Double(Int32(bitPattern: Self.middleEndian32(data, offset + 16))) / 128  // 2^7
            add(latitude: latitude, longitude: longitude, altitude: altitude, speed: kmh / 3.6,
                isPOI: type == .multiHzPOI)

        case .full, .poi:
            let time = Self.middleEndian32(data, offset + 2)
            week = Int(time & 0x3FF)
            secondOfWeek = Double(time >> 12)
            x = Int(Int32(bitPattern: Self.middleEndian32(data, offset + 6)))
            y = Int(Int32(bitPattern: Self.middleEndian32(data, offset + 10)))
            z = Int(Int32(bitPattern: Self.middleEndian32(data, offset + 14)))
            hasPosition = true
            addECEF(speed: speed, isPOI: type == .poi)

        case .compact:
            guard hasPosition else { return warnings.add(.malformedRecord, at: nil) }
            let dt = Int(data.u16be(offset + 2) ?? 0)
            let p = (0..<4).map { Int(data.u8(offset + 4 + $0) ?? 0) }
            x += Self.signed10(p[1] >> 6 | p[0] << 2)
            y += Self.signed10((p[1] & 0x3F) | (p[2] & 0xF0) << 2)
            z += Self.signed10(p[3] | (p[2] & 0x03) << 8)
            secondOfWeek += Double(dt)
            addECEF(speed: speed, isPOI: false)
        }
    }

    /// 10-bit deltas: values above 511 are negative (`511 - value`), as in the source.
    static func signed10(_ value: Int) -> Int {
        value > 511 ? 511 - value : value
    }

    private mutating func addECEF(speed: Double, isPOI: Bool) {
        let (latitude, longitude, altitude) = Self.geodetic(x: Double(x), y: Double(y), z: Double(z))
        add(latitude: latitude, longitude: longitude, altitude: altitude, speed: speed, isPOI: isPOI)
    }

    private mutating func add(latitude: Double, longitude: Double, altitude: Double, speed: Double, isPOI: Bool) {
        let absoluteWeek = GPSTime.absoluteWeek(tenBit: week, reference: reference)
        let time = GPSTime.date(absoluteWeek: absoluteWeek, secondOfWeek: secondOfWeek)
        guard latitude.isFinite, longitude.isFinite, abs(latitude) <= 90, abs(longitude) <= 180 else {
            return warnings.add(.invalidCoordinate, at: nil)
        }
        let point = TrackPoint(latitude: latitude, longitude: longitude, elevation: altitude.isFinite ? altitude : nil,
                               time: time, quality: PositionQuality(speed: speed))
        points.append(point)
        if isPOI {
            poiCount += 1
            waypoints.append(Waypoint(latitude: latitude, longitude: longitude, elevation: point.elevation, time: time,
                                      name: "POI \(poiCount)", quality: point.quality))
        }
    }

    /// ECEF to WGS 84 latitude, longitude (degrees) and ellipsoidal height (`ECEF_to_LLA`, Bowring's method).
    static func geodetic(x: Double, y: Double, z: Double) -> (Double, Double, Double) {
        let a = 6_378_137.0
        let b = 6_356_752.31424518
        let e2 = (a * a - b * b) / (a * a)
        let ep2 = (a * a - b * b) / (b * b)
        let p = (x * x + y * y).squareRoot()
        let theta = atan2(z * a, p * b)
        let latitude = atan2(z + ep2 * b * pow(sin(theta), 3), p - e2 * a * pow(cos(theta), 3))
        let longitude = atan2(y, x)
        let height = p / cos(latitude) - a / (1 - e2 * pow(sin(latitude), 2)).squareRoot()
        return (latitude * 180 / .pi, longitude * 180 / .pi, height)
    }

    /// Detection (design D5): consecutive valid items up to the first 0xFF, the first one full or multi-Hz,
    /// and a plausible position.
    static func looksLikeDump(_ data: ByteReader) -> Bool {
        var offset = 0
        var plausible = false
        var isFirst = true
        while let first = data.u8(offset), first != 0xFF {
            guard let type = ItemType(rawValue: first >> 4) else { return false }
            if offset + type.length > data.count { break }  // cut off by the prefix
            if isFirst {
                guard type != .compact else { return false }
                isFirst = false
                switch type {
                case .full, .poi:
                    let coordinates = [6, 10, 14].map { Double(Int32(bitPattern: middleEndian32(data, offset + $0))) }
                    let radius = coordinates.reduce(0) { $0 + $1 * $1 }.squareRoot()
                    plausible = (6_300_000...6_450_000).contains(radius)
                default:
                    let latitude = Double(Int32(bitPattern: middleEndian32(data, offset + 8))) / 1_048_576
                    let longitude = Double(Int32(bitPattern: middleEndian32(data, offset + 12))) / 1_048_576
                    plausible = abs(latitude) <= 90 && abs(longitude) <= 180
                }
                if !plausible { return false }
            }
            offset += type.length
        }
        return plausible
    }
}
