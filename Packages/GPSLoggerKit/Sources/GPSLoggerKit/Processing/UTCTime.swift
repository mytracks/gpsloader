import Foundation

/// Fast, locale and calendar independent UTC date arithmetic (proleptic Gregorian calendar).
enum UTCTime {
    /// Days since 1970-01-01 for a civil date ("days from civil", public domain algorithm by Howard Hinnant).
    static func days(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// Whether the components form a valid date and time (seconds may be fractional, below 61 for leap seconds).
    static func isValid(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Double = 0) -> Bool {
        guard (1...12).contains(month), day >= 1, (0...23).contains(hour), (0...59).contains(minute),
              second >= 0, second < 61 else { return false }
        return day <= daysInMonth(year: year, month: month)
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// The point in time, or `nil` if the components are invalid.
    static func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Double = 0) -> Date? {
        guard isValid(year: year, month: month, day: day, hour: hour, minute: minute, second: second) else { return nil }
        let seconds = Double(days(year: year, month: month, day: day)) * 86_400
            + Double(hour * 3600 + minute * 60) + second
        return Date(timeIntervalSince1970: seconds)
    }
}

/// Parser for ISO 8601 / XML Schema `dateTime` values as used in GPX.
enum ISO8601 {
    /// Parses `YYYY-MM-DDThh:mm:ss[.fff][Z|±hh:mm]`. Values without zone are UTC.
    /// Also accepts a date without time (`YYYY-MM-DD`) as midnight UTC.
    static func date(_ text: some StringProtocol) -> Date? {
        let s = Array(text.utf8.drop { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D })
        var end = s.count
        while end > 0, [0x20, 0x09, 0x0A, 0x0D].contains(s[end - 1]) { end -= 1 }
        var i = 0
        func digits(_ count: Int) -> Int? {
            guard i + count <= end else { return nil }
            var value = 0
            for _ in 0..<count {
                let c = s[i]
                guard c >= 0x30, c <= 0x39 else { return nil }
                value = value * 10 + Int(c - 0x30)
                i += 1
            }
            return value
        }
        func expect(_ c: UInt8) -> Bool {
            guard i < end, s[i] == c else { return false }
            i += 1
            return true
        }

        var sign = 1
        if i < end, s[i] == 0x2D { sign = -1; i += 1 }
        guard let yearValue = digits(4), expect(0x2D), let month = digits(2), expect(0x2D), let day = digits(2) else {
            return nil
        }
        let year = sign * yearValue
        var hour = 0, minute = 0
        var second = 0.0
        var offset = 0
        if i < end {
            guard expect(0x54) || expect(0x74) || expect(0x20) else { return nil }
            guard let h = digits(2), expect(0x3A), let m = digits(2), expect(0x3A), let sec = digits(2) else { return nil }
            hour = h
            minute = m
            second = Double(sec)
            if i < end, s[i] == 0x2E || s[i] == 0x2C {
                i += 1
                var fraction = 0
                var divisor = 1
                var count = 0
                while i < end, s[i] >= 0x30, s[i] <= 0x39 {
                    if count < 9 {
                        fraction = fraction * 10 + Int(s[i] - 0x30)
                        divisor *= 10
                    }
                    count += 1
                    i += 1
                }
                guard count > 0 else { return nil }
                second += Double(fraction) / Double(divisor)
            }
            if i < end {
                if expect(0x5A) || expect(0x7A) {
                    offset = 0
                } else if s[i] == 0x2B || s[i] == 0x2D {
                    let offsetSign = s[i] == 0x2D ? -1 : 1
                    i += 1
                    guard let oh = digits(2) else { return nil }
                    _ = expect(0x3A)
                    guard let om = digits(2), oh <= 14, om <= 59 else { return nil }
                    offset = offsetSign * (oh * 3600 + om * 60)
                } else {
                    return nil
                }
            }
        }
        guard i == end else { return nil }
        // 24:00:00 is allowed by XML Schema and means midnight of the next day.
        if hour == 24, minute == 0, second == 0 {
            return UTCTime.date(year: year, month: month, day: day).map { $0.addingTimeInterval(86_400 - Double(offset)) }
        }
        return UTCTime.date(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
            .map { $0.addingTimeInterval(-Double(offset)) }
    }
}
