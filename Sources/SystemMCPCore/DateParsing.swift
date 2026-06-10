import Foundation

/// Date parsing/formatting shared by the CLI and MCP layers.
///
/// Accepted input formats for `parse(_:)`:
///   - ISO8601 with time:      `2026-06-10T10:00:00`, `2026-06-10T10:00`, `2026-06-10 10:00`
///   - Date only:              `2026-06-10` (resolves to start of day, local time)
///   - Relative keywords:      `today`, `tomorrow`, `yesterday` (start of day, local time)
public enum DateParsing {
    public static func parse(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let calendar = Calendar.current
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

        for formatter in cachedFormatters {
            // Round-trip check: ICU accepts mismatched separators (e.g. "2026/06/10")
            // even with isLenient = false, so reject anything that doesn't re-format
            // to the exact input.
            if let date = formatter.date(from: trimmed), formatter.string(from: date) == trimmed {
                return date
            }
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

    private static let cachedFormatters: [DateFormatter] = {
        let patterns = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
        ]
        return patterns.map { pattern in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone.current
            f.dateFormat = pattern
            return f
        }
    }()
}
