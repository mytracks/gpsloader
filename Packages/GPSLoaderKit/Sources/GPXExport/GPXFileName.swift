import Foundation

/// Suggested file names for exported recordings (spec `logger-session`, "Ergebnis speichern").
public enum GPXFileName {
    /// "<device> yyyy-MM-dd HH-mm.gpx" in the given time zone (default: the user's).
    /// Characters that are not allowed or awkward in file names are replaced.
    public static func suggested(device: String, date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let stamp = String(format: "%04d-%02d-%02d %02d-%02d",
                           c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
        let cleaned = device
            .map { "/:\\\n\r\t".contains($0) ? "-" : $0 }
            .reduce(into: "") { $0.append($1) }
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        let name = cleaned.isEmpty ? "GPS" : cleaned
        return "\(name) \(stamp).gpx"
    }
}
