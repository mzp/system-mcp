import CoreGraphics
import CoreLocation
import EventKit
import Foundation
import Testing

@testable import SystemMCPCore

// These tests only create in-memory EventKit objects (no fetch/save), which does not
// require TCC authorization, so they run fine in headless environments.

@Suite struct ReminderResponseTests {
    @Test func convertsEKReminderFields() {
        let store = EKEventStore()
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = "Groceries"

        let reminder = EKReminder(eventStore: store)
        reminder.title = "buy milk"
        reminder.notes = "2 bottles"
        reminder.calendar = list
        reminder.priority = 1
        reminder.url = URL(string: "https://example.com/x")
        var due = DateComponents(year: 2026, month: 6, day: 10, hour: 9, minute: 0)
        due.calendar = Calendar.current
        reminder.dueDateComponents = due

        let response = ReminderResponse(reminder)
        #expect(response.id == reminder.calendarItemIdentifier)
        #expect(!response.id.isEmpty)
        #expect(response.title == "buy milk")
        #expect(response.notes == "2 bottles")
        #expect(response.list == "Groceries")
        #expect(response.listId == list.calendarIdentifier)
        #expect(response.completed == false)
        #expect(response.completionDate == nil)
        #expect(response.priority == "high")
        #expect(response.url == "https://example.com/x")
        #expect(response.dueDate == due.date)
        #expect(response.location == nil)  // no location alarm
        #expect(response.proximity == nil)
    }

    @Test func convertsLocationAlarm() {
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        reminder.title = "牛乳を買う"

        let structured = EKStructuredLocation(title: "東京都港区芝公園4-2-8")
        structured.geoLocation = CLLocation(latitude: 35.6586, longitude: 139.7454)
        structured.radius = 200
        let alarm = EKAlarm()
        alarm.structuredLocation = structured
        alarm.proximity = .enter
        reminder.addAlarm(alarm)

        let response = ReminderResponse(reminder)
        #expect(response.location == "東京都港区芝公園4-2-8")
        #expect(response.latitude == 35.6586)
        #expect(response.longitude == 139.7454)
        #expect(response.proximity == "enter")
        #expect(response.radius == 200)
    }

    @Test func zeroRadiusMeansSystemDefault() {
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        let structured = EKStructuredLocation(title: "Office")
        structured.geoLocation = CLLocation(latitude: 35.0, longitude: 139.0)
        let alarm = EKAlarm()
        alarm.structuredLocation = structured
        alarm.proximity = .leave
        reminder.addAlarm(alarm)

        let response = ReminderResponse(reminder)
        #expect(response.proximity == "leave")
        #expect(response.radius == nil)
    }

    @Test func handlesEmptyReminder() {
        let store = EKEventStore()
        let response = ReminderResponse(EKReminder(eventStore: store))
        #expect(response.title == "")
        #expect(response.notes == nil)
        #expect(response.list == "")
        #expect(response.listId == "")
        #expect(response.dueDate == nil)
        #expect(response.priority == "none")
        #expect(response.url == nil)
    }
}

@Suite struct EventResponseTests {
    @Test func convertsEKEventFields() {
        let store = EKEventStore()
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Work"

        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let event = EKEvent(eventStore: store)
        event.title = "standup"
        event.notes = "daily"
        event.calendar = calendar
        event.startDate = start
        event.endDate = start.addingTimeInterval(1800)
        event.isAllDay = false
        event.location = "Zoom"
        event.url = URL(string: "https://example.com/meet")

        let response = EventResponse(event)
        #expect(response.id == "")  // unsaved events have no identifier
        #expect(response.title == "standup")
        #expect(response.notes == "daily")
        #expect(response.calendar == "Work")
        #expect(response.calendarId == calendar.calendarIdentifier)
        #expect(response.startDate == start)
        #expect(response.endDate == start.addingTimeInterval(1800))
        #expect(response.isAllDay == false)
        #expect(response.location == "Zoom")
        #expect(response.latitude == nil)  // plain-text location carries no coordinates
        #expect(response.longitude == nil)
        #expect(response.url == "https://example.com/meet")
        #expect(response.status == nil)  // EKEventStatus.none -> nil
    }

    @Test func convertsTimeZone() {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.timeZone = TimeZone(identifier: "America/New_York")
        #expect(EventResponse(event).timeZone == "America/New_York")
    }

    @Test func convertsStructuredLocationCoordinates() {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        let structured = EKStructuredLocation(title: "東京都港区芝公園4-2-8")
        structured.geoLocation = CLLocation(latitude: 35.6586, longitude: 139.7454)
        event.structuredLocation = structured

        let response = EventResponse(event)
        #expect(response.location == "東京都港区芝公園4-2-8")  // title propagates to location
        #expect(response.latitude == 35.6586)
        #expect(response.longitude == 139.7454)
    }

    @Test func handlesEmptyEvent() {
        let store = EKEventStore()
        let response = EventResponse(EKEvent(eventStore: store))
        #expect(response.id == "")
        #expect(response.title == "")
        #expect(response.calendar == "")
        #expect(response.startDate == nil)
        #expect(response.endDate == nil)
        #expect(response.timeZone == TimeZone.current.identifier)  // EKEvent defaults to the local zone
        #expect(response.status == nil)
    }
}

@Suite struct CalendarResponseTests {
    @Test func convertsEKCalendarFields() {
        let store = EKEventStore()
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = "Groceries"
        calendar.cgColor = CGColor(red: 1, green: 0.5, blue: 0, alpha: 1)

        let response = CalendarResponse(calendar, defaultId: calendar.calendarIdentifier)
        #expect(response.id == calendar.calendarIdentifier)
        #expect(response.title == "Groceries")
        #expect(response.type == "local")
        #expect(response.color == "#FF8000")
        #expect(response.isDefault == true)
    }

    @Test func isDefaultIsFalseWhenDefaultIdDiffersOrIsNil() {
        let store = EKEventStore()
        let calendar = EKCalendar(for: .event, eventStore: store)
        #expect(CalendarResponse(calendar, defaultId: nil).isDefault == false)
        #expect(CalendarResponse(calendar, defaultId: "other-id").isDefault == false)
    }
}
