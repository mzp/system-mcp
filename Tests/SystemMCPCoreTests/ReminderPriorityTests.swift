import Testing

@testable import SystemMCPCore

@Suite struct ReminderPriorityTests {
    @Test func mapsToEventKitValues() {
        #expect(ReminderPriority.none.ekValue == 0)
        #expect(ReminderPriority.high.ekValue == 1)
        #expect(ReminderPriority.medium.ekValue == 5)
        #expect(ReminderPriority.low.ekValue == 9)
    }

    @Test func mapsFromEventKitValues() {
        #expect(ReminderPriority(ekValue: 0) == .none)
        // Apple convention: 1-4 = high, 5 = medium, 6-9 = low
        #expect(ReminderPriority(ekValue: 1) == .high)
        #expect(ReminderPriority(ekValue: 4) == .high)
        #expect(ReminderPriority(ekValue: 5) == .medium)
        #expect(ReminderPriority(ekValue: 6) == .low)
        #expect(ReminderPriority(ekValue: 9) == .low)
    }

    @Test func roundTripsAllCases() {
        for priority in ReminderPriority.allCases {
            #expect(ReminderPriority(ekValue: priority.ekValue) == priority)
        }
    }

    @Test func parsesStringsCaseInsensitively() {
        #expect(ReminderPriority(string: "high") == .high)
        #expect(ReminderPriority(string: "HIGH") == .high)
        #expect(ReminderPriority(string: "Medium") == .medium)
        #expect(ReminderPriority(string: "none") == ReminderPriority.none)
        #expect(ReminderPriority(string: "urgent") == nil)
        #expect(ReminderPriority(string: "") == nil)
    }
}
