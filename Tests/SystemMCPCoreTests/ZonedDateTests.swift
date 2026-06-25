import Foundation
import Testing

@testable import SystemMCPCore

@Suite struct ZonedDateTests {
    @Test func encodesInItsAnchorZoneOffset() throws {
        // 2026-06-16T03:08:00Z == 2026-06-15T20:08:00-07:00 in Pacific (PDT).
        let instant = Date(timeIntervalSince1970: 1_781_579_280)
        let pacific = TimeZone(identifier: "America/Los_Angeles")!
        let data = try DateParsing.jsonEncoder.encode(ZonedDate(date: instant, timeZone: pacific))
        let json = String(decoding: data, as: UTF8.self)
        #expect(json == "\"2026-06-15T20:08:00-07:00\"")
    }

    @Test func tokyoOffset() throws {
        let instant = Date(timeIntervalSince1970: 1_781_579_280)
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let data = try DateParsing.jsonEncoder.encode(ZonedDate(date: instant, timeZone: tokyo))
        let json = String(decoding: data, as: UTF8.self)
        #expect(json == "\"2026-06-16T12:08:00+09:00\"")
    }

    @Test func floatingEncodesWithoutOffset() throws {
        // A floating date emits a zone-less wall-clock (no offset / no `Z`), read in the local zone.
        var components = DateComponents(year: 2026, month: 6, day: 10, hour: 9, minute: 0)
        components.calendar = Calendar.current
        let instant = try #require(components.date)
        let data = try DateParsing.jsonEncoder.encode(ZonedDate(date: instant, timeZone: nil))
        let json = String(decoding: data, as: UTF8.self)
        #expect(json == "\"2026-06-10T09:00:00\"")
    }

    @Test func roundTripsPreservesInstant() throws {
        let instant = Date(timeIntervalSince1970: 1_781_579_280)
        let original = ZonedDate(date: instant, timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        let data = try DateParsing.jsonEncoder.encode(original)
        let decoded = try DateParsing.jsonDecoder.decode(ZonedDate.self, from: data)
        #expect(decoded.date == instant)
    }
}
