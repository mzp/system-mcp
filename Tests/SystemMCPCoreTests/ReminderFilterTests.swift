import Testing

@testable import SystemMCPCore

@Suite struct ReminderFilterTests {
    @Test func parsesKnownKeywords() {
        #expect(ReminderFilter.named("today") == .today)
        #expect(ReminderFilter.named("tomorrow") == .tomorrow)
        #expect(ReminderFilter.named("week") == .week)
        #expect(ReminderFilter.named("overdue") == .overdue)
        #expect(ReminderFilter.named("upcoming") == .upcoming)
        #expect(ReminderFilter.named("completed") == .completed)
        #expect(ReminderFilter.named("all") == .all)
    }

    @Test func keywordsAreCaseInsensitive() {
        #expect(ReminderFilter.named("Today") == .today)
        #expect(ReminderFilter.named("OVERDUE") == .overdue)
    }

    @Test(arguments: ["", "next-week", "todays", " today"])
    func rejectsUnknownKeywords(_ keyword: String) {
        #expect(ReminderFilter.named(keyword) == nil)
    }
}
