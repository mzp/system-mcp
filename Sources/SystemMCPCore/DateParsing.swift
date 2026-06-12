import Foundation

/// Date parsing/formatting shared by the CLI and MCP layers.
///
/// Accepted input formats for `parse(_:timeZone:)`:
///   - ISO8601 with time:      `2026-06-10T10:00:00`, `2026-06-10T10:00`, `2026-06-10 10:00`
///   - ISO8601 with offset:    `2026-06-10T10:00:00-05:00`, `2026-06-10T10:00Z` (offset wins over `timeZone`)
///   - Date only:              `2026-06-10` (resolves to start of day)
///   - Relative keywords:      `today`, `tomorrow`, `yesterday` (start of day)
///
/// Inputs without an explicit offset are interpreted in `timeZone` (local time by default).
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

    /// Date components (down to the minute, local calendar) used to set a reminder's due date.
    public static func dueComponents(from date: Date) -> DateComponents {
        Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date)
    }

    /// JSON encoder/decoder with ISO8601 dates, shared so CLI and MCP emit identical output.
    public static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
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
