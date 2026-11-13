import Foundation

/// A catalog of file formats: the formats of this package, optionally followed by formats of other packages.
///
/// Detection, lookup by identifier and reading work on any catalog the same way as on
/// ``FileFormats/all``. Catalogs are immutable values; build the catalog once and pass it on.
///
/// ```swift
/// let catalog = FormatCatalog.standard.adding([MyFormat()])
/// let format = catalog.detect(prefix: input.data, fileName: input.name)
/// ```
public struct FormatCatalog: Sendable {
    /// The formats in detection order.
    public let all: [any FileFormat]

    /// Creates a catalog. Duplicate identifiers are a programming error.
    public init(_ formats: [any FileFormat]) {
        let duplicates = Self.duplicateIDs(in: formats)
        precondition(duplicates.isEmpty, "Duplicate file format identifiers: \(duplicates)")
        all = formats
    }

    /// The formats of this package (``FileFormats/all``).
    public static let standard = FormatCatalog(FileFormats.all)

    /// A catalog with additional formats after the existing ones.
    public func adding(_ formats: [any FileFormat]) -> FormatCatalog {
        FormatCatalog(all + formats)
    }

    /// The format with the given identifier.
    public func format(withID id: FileFormatID) -> (any FileFormat)? {
        all.first { $0.id == id }
    }

    /// Suggests a format by content. The file extension only decides which formats are checked first;
    /// within each group the catalog order applies.
    /// - Returns: `nil` if no format recognizes the content ("unknown").
    public func detect(prefix: Data, fileName: String? = nil) -> (any FileFormat)? {
        let head = prefix.prefix(FileFormats.sniffLength)
        let fileExtension = fileName.map { ($0 as NSString).pathExtension.lowercased() } ?? ""
        let ordered = all.filter { $0.fileExtensions.contains(fileExtension) }
            + all.filter { !$0.fileExtensions.contains(fileExtension) }
        return ordered.first { $0.matches(prefix: head) }
    }

    /// Identifiers that occur more than once, in order of their second occurrence.
    static func duplicateIDs(in formats: [any FileFormat]) -> [FileFormatID] {
        var seen = Set<FileFormatID>()
        var duplicates: [FileFormatID] = []
        for format in formats where !seen.insert(format.id).inserted && !duplicates.contains(format.id) {
            duplicates.append(format.id)
        }
        return duplicates
    }
}
