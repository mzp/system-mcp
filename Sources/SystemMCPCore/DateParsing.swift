import Foundation

/// Date parsing/formatting shared by the CLI and MCP layers.
///
/// Accepted input formats for `parse(_:timeZone:)`:
///   - ISO8601 with time:      `2026-06-10T10:00:00`, `2026-06-10T10:00`, `2026-06-10 10:00`
///   - ISO8601 with offset:    `2026-06-10T10:00:00-05:00`, `2026-06-10T10:00Z` (offset wins over `timeZone`)
///   - Date only:              `2026-06-10` (resolves to start of day)
///   - Relative keywords:      `today`, `tomorrow`, `yesterday` (start of day)
///   - Relative offset:        `+1h`, `+30m`, `+1h30m`, `-2d` (sign required; resolved from now)
///
/// Inputs without an explicit offset are interpreted in `timeZone` (local time by default).
/// Relative offsets are resolved from the current time and ignore `timeZone` (they measure
/// elapsed wall-clock time).
public enum DateParsing {
    public static func parse(_ string: String, timeZone: TimeZone = .current) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        var calendar = Calendar.current
        calendar.timeZone = timeZone
        switch trimmed.lowercased() {
        case "today":
            return calendar.startOfDay(for: Date())
        case "tomorrow":
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))
        case "yesterday":
            return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))
        default:
            break
        }

        if let date = parseRelative(trimmed, now: Date()) {
            return date
        }

        if let date = parseWithOffset(trimmed) {
            return date
        }

        for pattern in naivePatterns {
            let formatter = makeFormatter(pattern, timeZone: timeZone)
            // Round-trip check: ICU accepts mismatched separators (e.g. "2026/06/10")
            // even with isLenient = false, so reject anything that doesn't re-format
            // to the exact input.
            if let date = formatter.date(from: trimmed), formatter.string(from: date) == trimmed {
                return date
            }
        }
        return nil
    }

    /// Resolves a user-supplied time zone string: IANA identifier (`America/New_York`,
    /// case-insensitive) or abbreviation (`EST`, `JST`). Abbreviations map to their
    /// region zone, so DST is honored (e.g. `EST` still gives EDT times in summer).
    public static func timeZone(from string: String) -> TimeZone? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let zone = TimeZone(identifier: trimmed) { return zone }
        if let zone = TimeZone(abbreviation: trimmed.uppercased()) { return zone }
        if let id = TimeZone.knownTimeZoneIdentifiers.first(where: {
            $0.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return TimeZone(identifier: id)
        }
        return nil
    }

    /// Date components (down to the minute) used to set a reminder's due date.
    ///
    /// With `timeZone == nil` the reminder is *floating*: the components carry no zone, so the
    /// reminder fires at that wall-clock time in whatever zone the device is in (the Reminders
    /// app's default). With a `timeZone` the components are extracted in—and anchored to—that
    /// zone, fixing the reminder to an absolute moment so its order stays stable against
    /// time-zoned calendar events. See docs/eventkit.md.
    public static func dueComponents(from date: Date, timeZone: TimeZone? = nil) -> DateComponents {
        var calendar = Calendar.current
        if let timeZone { calendar.timeZone = timeZone }
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.timeZone = timeZone
        return components
    }

    /// Formats `date` as ISO8601 (`yyyy-MM-dd'T'HH:mm:ssZZZZZ`) anchored to `timeZone`, so the
    /// string carries the wall-clock time *and* its UTC offset (`2026-06-15T20:08:00-07:00`, or
    /// `…Z` for UTC). This lets a reader see the local time directly without converting from UTC.
    public static func iso8601String(_ date: Date, timeZone: TimeZone) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = timeZone
        return f.string(from: date)
    }

    /// Formats `date` as a *floating* (zone-less) ISO8601 wall-clock string with **no** offset
    /// (`2026-06-10T09:00:00`). The wall-clock is read in the local zone, recovering the components
    /// a floating reminder/event was set with. The absent offset signals "this time has no zone —
    /// don't convert it" (paired with `floating: true` in the response). See `ZonedDate`.
    public static func floatingString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.string(from: date)
    }

    /// JSON encoder/decoder with ISO8601 dates, shared so CLI and MCP emit identical output.
    /// Dates are emitted in the local zone with an explicit offset (not UTC `Z`) so the wall-clock
    /// time is readable as-is. `ZonedDate` fields override this with their own anchor zone.
    public static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(iso8601String(date, timeZone: .current))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    public static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Parses inputs carrying their own UTC offset (`...T10:00:00-05:00`, `...T10:00Z`).
    /// The round-trip check doesn't work here (the formatter can't know the input's
    /// offset up front), so a strict shape check stands in for it.
    private static func parseWithOffset(_ string: String) -> Date? {
        // Regex isn't Sendable, so build it locally instead of caching it statically.
        let offsetShape = /\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2})?(Z|[+-]\d{2}:\d{2})/
        guard string.wholeMatch(of: offsetShape) != nil else { return nil }
        for pattern in ["yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd'T'HH:mmXXXXX"] {
            let formatter = makeFormatter(pattern, timeZone: .current)
            if let date = formatter.date(from: string.replacingOccurrences(of: " ", with: "T")) {
                return date
            }
        }
        return nil
    }

    /// Parses a sign-prefixed relative offset (`+1h`, `+30m`, `+1h30m`, `-2d`) and adds it to
    /// `now`. The sign is required so bare `1h` stays invalid and never collides with the
    /// ISO8601 / date-only / keyword forms. Units: `w` (weeks), `d` (days), `h` (hours),
    /// `m` (minutes). `now` is injected to keep the math testable.
    static func parseRelative(_ string: String, now: Date) -> Date? {
        // Regex isn't Sendable, so build it locally instead of caching it statically.
        let shape = /^([+-])((?:\d+[wdhm])+)$/
        guard let match = string.wholeMatch(of: shape) else { return nil }
        let sign = match.1 == "-" ? -1 : 1

        var components = DateComponents()
        for segment in match.2.matches(of: /(\d+)([wdhm])/) {
            guard let value = Int(segment.1) else { return nil }
            let signed = value * sign
            switch segment.2 {
            case "w": components.weekOfYear = (components.weekOfYear ?? 0) + signed
            case "d": components.day = (components.day ?? 0) + signed
            case "h": components.hour = (components.hour ?? 0) + signed
            case "m": components.minute = (components.minute ?? 0) + signed
            default: return nil
            }
        }
        return Calendar.current.date(byAdding: components, to: now)
    }

    private static let naivePatterns = [
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd",
    ]

    private static func makeFormatter(_ pattern: String, timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = pattern
        return f
    }
}
