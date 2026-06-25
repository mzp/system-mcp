import Foundation
import Testing

@testable import SystemMCPCore

@Suite struct DateParsingTests {
    private let calendar = Calendar.current

    private func components(_ date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    }

    @Test func parsesISO8601WithSeconds() throws {
        let date = try #require(DateParsing.parse("2026-06-10T10:30:45"))
        let c = components(date)
        #expect(c.year == 2026)
        #expect(c.month == 6)
        #expect(c.day == 10)
        #expect(c.hour == 10)
        #expect(c.minute == 30)
        #expect(c.second == 45)
    }

    @Test func parsesISO8601WithoutSeconds() throws {
        let date = try #require(DateParsing.parse("2026-06-10T10:30"))
        let c = components(date)
        #expect(c.hour == 10)
        #expect(c.minute == 30)
        #expect(c.second == 0)
    }

    @Test func parsesSpaceSeparatedDateTime() throws {
        let withSeconds = try #require(DateParsing.parse("2026-06-10 10:30:45"))
        let withoutSeconds = try #require(DateParsing.parse("2026-06-10 10:30"))
        #expect(components(withSeconds).second == 45)
        #expect(components(withoutSeconds).minute == 30)
    }

    @Test func parsesDateOnlyAsStartOfDay() throws {
        let date = try #require(DateParsing.parse("2026-06-10"))
        let c = components(date)
        #expect(c.year == 2026)
        #expect(c.month == 6)
        #expect(c.day == 10)
        #expect(c.hour == 0)
        #expect(c.minute == 0)
    }

    @Test func parsesRelativeKeywords() throws {
        let today = try #require(DateParsing.parse("today"))
        let tomorrow = try #require(DateParsing.parse("tomorrow"))
        let yesterday = try #require(DateParsing.parse("yesterday"))

        let startOfToday = calendar.startOfDay(for: Date())
        #expect(today == startOfToday)
        #expect(tomorrow == calendar.date(byAdding: .day, value: 1, to: startOfToday))
        #expect(yesterday == calendar.date(byAdding: .day, value: -1, to: startOfToday))
    }

    @Test func relativeKeywordsAreCaseInsensitive() {
        #expect(DateParsing.parse("Today") != nil)
        #expect(DateParsing.parse("TOMORROW") != nil)
    }

    @Test func parsesRelativeOffsetFromInjectedNow() throws {
        let now = try #require(DateParsing.parse("2026-06-10T10:00"))

        #expect(DateParsing.parseRelative("+1h", now: now) == calendar.date(byAdding: .hour, value: 1, to: now))
        #expect(DateParsing.parseRelative("+30m", now: now) == calendar.date(byAdding: .minute, value: 30, to: now))
        #expect(DateParsing.parseRelative("+2d", now: now) == calendar.date(byAdding: .day, value: 2, to: now))
        #expect(DateParsing.parseRelative("+1w", now: now) == calendar.date(byAdding: .day, value: 7, to: now))
        #expect(DateParsing.parseRelative("-15m", now: now) == calendar.date(byAdding: .minute, value: -15, to: now))
    }

    @Test func combinesRelativeOffsetSegments() throws {
        let now = try #require(DateParsing.parse("2026-06-10T10:00"))
        let expected = calendar.date(byAdding: .minute, value: 90, to: now)  // 1h30m
        #expect(DateParsing.parseRelative("+1h30m", now: now) == expected)
    }

    @Test func parseResolvesRelativeOffsetFromCurrentTime() throws {
        let parsed = try #require(DateParsing.parse("+1h"))
        // now-based, so it lands roughly an hour ahead; allow slack for clock drift during the test.
        #expect(abs(parsed.timeIntervalSinceNow - 3600) < 5)
    }

    @Test func trimsWhitespace() throws {
        let date = try #require(DateParsing.parse("  2026-06-10  "))
        #expect(components(date).day == 10)
    }

    @Test(arguments: [
        "", "   ", "not a date", "2026/06/10", "10:30", "2026-13-45",
        "2026-06-10T10:00+9:00", "2026-06-10+09:00",
        "1h", "+1x", "+h", "+", "+1", "++1h", "+1.5h", "1h30m",
    ])
    func rejectsInvalidInput(_ input: String) {
        #expect(DateParsing.parse(input) == nil)
    }

    @Test func dueComponentsKeepDownToMinute() throws {
        let date = try #require(DateParsing.parse("2026-06-10T10:30:45"))
        let due = DateParsing.dueComponents(from: date)
        #expect(due.year == 2026)
        #expect(due.month == 6)
        #expect(due.day == 10)
        #expect(due.hour == 10)
        #expect(due.minute == 30)
        #expect(due.second == nil)
    }

    @Test func dueComponentsAreFloatingWithoutTimeZone() throws {
        let date = try #require(DateParsing.parse("2026-06-10T10:30"))
        let due = DateParsing.dueComponents(from: date)
        #expect(due.timeZone == nil)
    }

    @Test func dueComponentsAnchorToGivenTimeZone() throws {
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        // 10:30 wall-clock in Tokyo.
        let date = try #require(DateParsing.parse("2026-06-10T10:30", timeZone: tokyo))
        let due = DateParsing.dueComponents(from: date, timeZone: tokyo)
        #expect(due.timeZone == tokyo)
        // Components are extracted in the anchored zone, so they read back as the same wall-clock.
        #expect(due.year == 2026)
        #expect(due.month == 6)
        #expect(due.day == 10)
        #expect(due.hour == 10)
        #expect(due.minute == 30)
    }

    @Test func jsonEncoderUsesISO8601WithOffsetAndSortedKeys() throws {
        struct Sample: Codable, Equatable {
            let b: Date
            let a: String
        }
        let original = Sample(b: Date(timeIntervalSince1970: 0), a: "x")
        let data = try DateParsing.jsonEncoder.encode(original)
        let json = String(decoding: data, as: UTF8.self)
        // Dates carry an explicit offset (local-zone offset or `Z` for UTC), never a bare instant.
        // Asserted via a tz-independent shape check rather than a fixed string.
        let offsetShape = /"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})"/
        #expect(json.firstMatch(of: offsetShape) != nil)
        // Round-trips back to the same instant regardless of the machine's zone.
        let decoded = try DateParsing.jsonDecoder.decode(Sample.self, from: data)
        #expect(decoded == original)
        // sortedKeys: "a" must appear before "b"
        let aIndex = try #require(json.range(of: "\"a\"")?.lowerBound)
        let bIndex = try #require(json.range(of: "\"b\"")?.lowerBound)
        #expect(aIndex < bIndex)
    }

    @Test func jsonDecoderRoundTripsEncoderOutput() throws {
        struct Sample: Codable, Equatable {
            let date: Date
        }
        let original = Sample(date: Date(timeIntervalSince1970: 1_750_000_000))
        let data = try DateParsing.jsonEncoder.encode(original)
        let decoded = try DateParsing.jsonDecoder.decode(Sample.self, from: data)
        #expect(decoded == original)
    }
}

@Suite struct DateParsingTimeZoneTests {
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    private let utc = TimeZone(identifier: "UTC")!

    private func utcDate(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func naiveDateTimeIsInterpretedInGivenTimeZone() throws {
        let date = try #require(DateParsing.parse("2026-06-10T10:00", timeZone: tokyo))
        #expect(date == utcDate(2026, 6, 10, 1, 0))  // 10:00 JST == 01:00 UTC
    }

    @Test func dateOnlyResolvesToStartOfDayInGivenTimeZone() throws {
        let date = try #require(DateParsing.parse("2026-06-10", timeZone: tokyo))
        #expect(date == utcDate(2026, 6, 9, 15, 0))  // midnight JST == 15:00 UTC previous day
    }

    @Test func relativeKeywordUsesGivenTimeZone() throws {
        let today = try #require(DateParsing.parse("today", timeZone: utc))
        var calendar = Calendar.current
        calendar.timeZone = utc
        #expect(today == calendar.startOfDay(for: Date()))
    }

    @Test func parsesExplicitOffset() throws {
        let withSeconds = try #require(DateParsing.parse("2026-06-10T10:00:00+09:00"))
        let withoutSeconds = try #require(DateParsing.parse("2026-06-10T10:00+09:00"))
        let zulu = try #require(DateParsing.parse("2026-06-10T10:00:00Z"))
        #expect(withSeconds == utcDate(2026, 6, 10, 1, 0))
        #expect(withoutSeconds == utcDate(2026, 6, 10, 1, 0))
        #expect(zulu == utcDate(2026, 6, 10, 10, 0))
    }

    @Test func explicitOffsetWinsOverTimeZoneParameter() throws {
        let date = try #require(DateParsing.parse("2026-06-10T10:00:00-05:00", timeZone: tokyo))
        #expect(date == utcDate(2026, 6, 10, 15, 0))
    }

    @Test func defaultTimeZoneMatchesLocalParsing() throws {
        let implicit = try #require(DateParsing.parse("2026-06-10T10:00"))
        let explicit = try #require(DateParsing.parse("2026-06-10T10:00", timeZone: .current))
        #expect(implicit == explicit)
    }

    @Test func resolvesTimeZoneFromIANAIdentifier() {
        #expect(DateParsing.timeZone(from: "Asia/Tokyo")?.identifier == "Asia/Tokyo")
        #expect(DateParsing.timeZone(from: "america/new_york")?.identifier == "America/New_York")
    }

    @Test func resolvesTimeZoneFromAbbreviation() {
        // "JST" resolves as a legacy identifier (UTC+9); "est" only matches as an abbreviation.
        #expect(DateParsing.timeZone(from: "JST")?.secondsFromGMT() == 9 * 3600)
        #expect(DateParsing.timeZone(from: "est")?.identifier == "America/New_York")
    }

    @Test(arguments: ["", "   ", "Mars/Olympus", "XYZ"])
    func rejectsUnknownTimeZone(_ input: String) {
        #expect(DateParsing.timeZone(from: input) == nil)
    }
}
