import Foundation

extension Collection where Element == UInt8 {
    /// Upper case hex representation separated by spaces, e.g. "93 01 0A".
    public var hexString: String {
        map { byte in
            let digits = String(byte, radix: 16, uppercase: true)
            return digits.count == 1 ? "0" + digits : digits
        }
        .joined(separator: " ")
    }

    /// Printable ASCII representation; non printable bytes become ".", CR/LF are shown as \r and \n.
    public var printableASCII: String {
        var result = ""
        for byte in self {
            switch byte {
            case 0x0D: result += "\\r"
            case 0x0A: result += "\\n"
            case 0x20...0x7E: result.append(Character(Unicode.Scalar(byte)))
            default: result += "."
            }
        }
        return result
    }
}

extension Array where Element == UInt8 {
    /// Parses hex digits, ignoring whitespace. Returns `nil` for invalid input.
    public init?(hexString: String) {
        let digits = hexString.filter { !$0.isWhitespace }
        guard digits.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(digits.count / 2)
        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)
            guard let value = UInt8(digits[index..<next], radix: 16) else { return nil }
            bytes.append(value)
            index = next
        }
        self = bytes
    }
}
