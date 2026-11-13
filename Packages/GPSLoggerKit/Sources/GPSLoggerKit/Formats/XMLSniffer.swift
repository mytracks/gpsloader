import Foundation

/// Detection helper for XML based formats (GPX, TCX, Suunto SML).
enum XMLSniffer {
    /// Local name (without namespace prefix) of the first element in the start of a document,
    /// skipping the XML declaration, processing instructions, comments and DOCTYPE.
    /// - Returns: `nil` if the prefix contains no element start.
    static func rootElementLocalName(in prefix: Data) -> String? {
        let text = String(decoding: prefix, as: UTF8.self)
        var rest = text[...]
        while let open = rest.firstIndex(of: "<") {
            rest = rest[rest.index(after: open)...]
            guard let next = rest.first else { return nil }
            if next == "?" || next == "!" {
                // XML declaration, comment, DOCTYPE: skip to the end of the markup.
                guard let close = rest.firstIndex(of: ">") else { return nil }
                rest = rest[rest.index(after: close)...]
                continue
            }
            let name = rest.prefix { !$0.isWhitespace && $0 != ">" && $0 != "/" }
            return String(name.split(separator: ":").last ?? name)
        }
        return nil
    }

    /// Local name of a parsed element name that may still carry a prefix.
    static func localName(_ elementName: String) -> String {
        elementName.split(separator: ":").last.map(String.init) ?? elementName
    }
}
