import EventKit
import Testing

@testable import SystemMCPCore

@Suite struct AlarmProximityTests {
    @Test func mapsToEKValues() {
        #expect(AlarmProximity.enter.ekValue == .enter)
        #expect(AlarmProximity.leave.ekValue == .leave)
    }

    @Test func mapsFromEKValues() {
        #expect(AlarmProximity(ekValue: .enter) == .enter)
        #expect(AlarmProximity(ekValue: .leave) == .leave)
        #expect(AlarmProximity(ekValue: .none) == nil)
    }

    @Test func roundTripsAllCases() {
        for proximity in AlarmProximity.allCases {
            #expect(AlarmProximity(ekValue: proximity.ekValue) == proximity)
        }
    }

    @Test func parsesStringsCaseInsensitively() {
        #expect(AlarmProximity(string: "enter") == .enter)
        #expect(AlarmProximity(string: "ENTER") == .enter)
        #expect(AlarmProximity(string: "Leave") == .leave)
        #expect(AlarmProximity(string: "arrive") == nil)
        #expect(AlarmProximity(string: "") == nil)
    }
}
