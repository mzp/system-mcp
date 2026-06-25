import Foundation

/// A `Date` together with the zone it should be displayed in. Encodes to an ISO8601 string whose
/// shape reflects whether the time is anchored to a zone:
///
/// - **Anchored** (`timeZone` non-nil): emits the zone's UTC offset (`2026-06-15T20:08:00-07:00`),
///   so the wall-clock time reads directly without converting from UTC.
/// - **Floating** (`timeZone == nil`): emits a zone-less wall-clock with **no** offset
///   (`2026-06-10T09:00:00`). The missing offset signals the time has no zone and must not be
///   converted — it fires at that wall-clock time wherever the device is.
///
/// Used for fields with a meaningful anchor — a reminder's due date or an event's start/end —
/// where the offset (or its absence) should reflect that item rather than the machine's local zone
/// (see `DateParsing.jsonEncoder`).
public struct ZonedDate: Sendable, Equatable {
    public let date: Date
    /// The anchor zone, or nil when the time is floating (zone-less wall-clock).
    public let timeZone: TimeZone?

    public init(date: Date, timeZone: TimeZone?) {
        self.date = date
        self.timeZone = timeZone
    }
}

extension ZonedDate: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let timeZone {
            try container.encode(DateParsing.iso8601String(date, timeZone: timeZone))
        } else {
            try container.encode(DateParsing.floatingString(date))
        }
    }

    public init(from decoder: Decoder) throws {
        // Parse with the shared parser, which handles both offset and zone-less forms. The original
        // zone identifier isn't recoverable from the string; callers that need it read the sibling
        // `timeZone` IANA field on the response. Zone-less input round-trips as floating (nil).
        let string = try decoder.singleValueContainer().decode(String.self)
        guard let date = DateParsing.parse(string) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "invalid date: \(string)"))
        }
        self.date = date
        self.timeZone = nil
    }
}
