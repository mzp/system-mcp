import Foundation
import Testing

@testable import SystemMCPCore

@Suite struct TimeAnchorTests {
    @Test func omittedResolvesToLocal() throws {
        #expect(try parseAnchorOrThrow(nil) == .local)
        #expect(try parseAnchorOrThrow("") == .local)
        #expect(try parseAnchorOrThrow("  ") == .local)
    }

    @Test func floatingSentinelsResolveToFloating() throws {
        #expect(try parseAnchorOrThrow("floating") == .floating)
        #expect(try parseAnchorOrThrow("Floating") == .floating)
        #expect(try parseAnchorOrThrow("none") == .floating)
        #expect(try parseAnchorOrThrow("  NONE ") == .floating)
    }

    @Test func explicitZoneResolvesToFixed() throws {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        #expect(try parseAnchorOrThrow("Asia/Tokyo") == .fixed(tokyo))
        // Abbreviations resolve to a zone with the matching offset (identifier may differ).
        guard case .fixed(let zone) = try parseAnchorOrThrow("JST") else {
            Issue.record("expected .fixed for JST")
            return
        }
        #expect(zone.secondsFromGMT() == 9 * 3600)
    }

    @Test func unknownZoneThrows() {
        #expect(throws: EventKitError.self) {
            _ = try parseAnchorOrThrow("Not/AZone")
        }
    }

    @Test func parseZoneIsLocalForLocalAndFloating() {
        #expect(TimeAnchor.local.parseZone == .current)
        #expect(TimeAnchor.floating.parseZone == .current)
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        #expect(TimeAnchor.fixed(tokyo).parseZone == tokyo)
    }

    @Test func dueZoneIsNilOnlyForFloating() {
        #expect(TimeAnchor.local.dueZone == .current)
        #expect(TimeAnchor.floating.dueZone == nil)
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        #expect(TimeAnchor.fixed(tokyo).dueZone == tokyo)
    }
}
