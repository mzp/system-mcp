import EventKit
import Foundation
import Logging

/// Filter presets for listing reminders.
public enum ReminderFilter: Sendable, Equatable {
    case today
    case tomorrow
    case week
    case overdue
    case upcoming
    case completed
    case all
    case range(start: Date?, end: Date?)

    /// Parse a filter keyword. Returns `nil` for unknown keywords.
    public static func named(_ keyword: String) -> ReminderFilter? {
        switch keyword.lowercased() {
        case "today": return .today
        case "tomorrow": return .tomorrow
        case "week": return .week
        case "overdue": return .overdue
        case "upcoming": return .upcoming
        case "completed": return .completed
        case "all": return .all
        default: return nil
        }
    }
}

/// Thin actor wrapper around `EKEventStore`. All EventKit access is funnelled through
/// here so the CLI and MCP layers only ever see Sendable response models.
public actor EventStoreService {
    private let store = EKEventStore()

    public init() {}

    // MARK: - Authorization

    public func authorizationStatus() -> AuthorizationStatusResponse {
        AuthorizationStatusResponse(
            events: Self.statusName(EKEventStore.authorizationStatus(for: .event)),
            reminders: Self.statusName(EKEventStore.authorizationStatus(for: .reminder)))
    }

    /// Requests access to both entity types (triggers the TCC prompt on first run) and
    /// returns the resulting status.
    @discardableResult
    public func requestAccess() async -> AuthorizationStatusResponse {
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            _ = try? await store.requestFullAccessToEvents()
        }
        if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
            _ = try? await store.requestFullAccessToReminders()
        }
        let status = authorizationStatus()
        log.info(
            "authorization",
            metadata: ["events": .string(status.events), "reminders": .string(status.reminders)])
        return status
    }

    private func ensureRemindersAccess() async throws {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            return
        case .notDetermined:
            let granted = (try? await store.requestFullAccessToReminders()) ?? false
            if !granted { throw EventKitError.accessDenied(entity: "reminders") }
        default:
            log.warning("reminders access denied", metadata: ["status": "\(EKEventStore.authorizationStatus(for: .reminder).rawValue)"])
            throw EventKitError.accessDenied(entity: "reminders")
        }
    }

    private func ensureEventsAccess() async throws {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return
        case .notDetermined:
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            if !granted { throw EventKitError.accessDenied(entity: "calendar events") }
        default:
            log.warning("calendar access denied", metadata: ["status": "\(EKEventStore.authorizationStatus(for: .event).rawValue)"])
            throw EventKitError.accessDenied(entity: "calendar events")
        }
    }

    private static func statusName(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .fullAccess: return "fullAccess"
        case .writeOnly: return "writeOnly"
        case .authorized: return "authorized"
        @unknown default: return "unknown"
        }
    }

    // MARK: - Calendars / Lists

    public func listCalendars() async throws -> [CalendarResponse] {
        log.debug("listCalendars")
        try await ensureEventsAccess()
        let defaultId = store.defaultCalendarForNewEvents?.calendarIdentifier
        let result = store.calendars(for: .event)
            .map { CalendarResponse($0, defaultId: defaultId) }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        log.debug("listCalendars result", metadata: ["count": "\(result.count)"])
        return result
    }

    public func listReminderLists() async throws -> [CalendarResponse] {
        log.debug("listReminderLists")
        try await ensureRemindersAccess()
        let defaultId = store.defaultCalendarForNewReminders()?.calendarIdentifier
        let result = store.calendars(for: .reminder)
            .map { CalendarResponse($0, defaultId: defaultId) }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        log.debug("listReminderLists result", metadata: ["count": "\(result.count)"])
        return result
    }

    public func createReminderList(name: String) async throws -> CalendarResponse {
        log.debug("createReminderList", metadata: ["name": .string(name)])
        try await ensureRemindersAccess()
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = name
        guard
            let source = store.defaultCalendarForNewReminders()?.source
                ?? store.sources.first(where: { !$0.calendars(for: .reminder).isEmpty })
                ?? store.sources.first
        else {
            throw EventKitError.saveFailed("no available source for a new reminder list")
        }
        calendar.source = source
        do {
            try store.saveCalendar(calendar, commit: true)
        } catch {
            throw EventKitError.saveFailed(error.localizedDescription)
        }
        return CalendarResponse(calendar, defaultId: store.defaultCalendarForNewReminders()?.calendarIdentifier)
    }

    public func renameReminderList(idOrName: String, newName: String) async throws -> CalendarResponse {
        log.debug("renameReminderList", metadata: ["list": .string(idOrName), "newName": .string(newName)])
        try await ensureRemindersAccess()
        let calendar = try reminderCalendar(idOrName: idOrName)
        calendar.title = newName
        do {
            try store.saveCalendar(calendar, commit: true)
        } catch {
            throw EventKitError.saveFailed(error.localizedDescription)
        }
        return CalendarResponse(calendar, defaultId: store.defaultCalendarForNewReminders()?.calendarIdentifier)
    }

    public func deleteReminderList(idOrName: String) async throws {
        log.debug("deleteReminderList", metadata: ["list": .string(idOrName)])
        try await ensureRemindersAccess()
        let calendar = try reminderCalendar(idOrName: idOrName)
        do {
            try store.removeCalendar(calendar, commit: true)
        } catch {
            throw EventKitError.removeFailed(error.localizedDescription)
        }
    }

    // MARK: - Reminders

    public func fetchReminders(filter: ReminderFilter, list: String? = nil) async throws -> [ReminderResponse] {
        log.debug("fetchReminders", metadata: ["filter": "\(filter)", "list": .string(list ?? "*")])
        try await ensureRemindersAccess()
        let calendars = try list.map { try [reminderCalendar(idOrName: $0)] }

        let predicate: NSPredicate
        if case .completed = filter {
            predicate = store.predicateForCompletedReminders(
                withCompletionDateStarting: nil, ending: nil, calendars: calendars)
        } else {
            predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: nil, ending: nil, calendars: calendars)
        }

        let reminders = await fetchReminderResponses(matching: predicate)
        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)

        let filtered = reminders.filter { reminder in
            switch filter {
            case .completed, .all:
                return true
            case .today:
                guard let due = reminder.dueDate else { return false }
                return calendar.isDate(due, inSameDayAs: now)
            case .tomorrow:
                guard let due = reminder.dueDate,
                    let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)
                else { return false }
                return calendar.isDate(due, inSameDayAs: tomorrow)
            case .week:
                guard let due = reminder.dueDate,
                    let weekEnd = calendar.date(byAdding: .day, value: 7, to: startOfToday)
                else { return false }
                return due >= startOfToday && due < weekEnd
            case .overdue:
                guard let due = reminder.dueDate else { return false }
                return due < now
            case .upcoming:
                guard let due = reminder.dueDate else { return false }
                return due >= now
            case .range(let start, let end):
                guard let due = reminder.dueDate else { return false }
                if let start, due < start { return false }
                if let end, due > end { return false }
                return true
            }
        }

        let result = filtered.sorted(by: Self.reminderOrder)
        log.debug("fetchReminders result", metadata: ["count": "\(result.count)"])
        return result
    }

    public func addReminder(
        title: String, list: String? = nil, due: Date? = nil, notes: String? = nil,
        priority: String? = nil
    ) async throws -> ReminderResponse {
        log.debug(
            "addReminder",
            metadata: [
                "title": .string(title), "list": .string(list ?? "<default>"),
                "due": "\(due as Any)", "priority": .string(priority ?? "none"),
            ])
        try await ensureRemindersAccess()
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = try list.map { try reminderCalendar(idOrName: $0) }
            ?? store.defaultCalendarForNewReminders()
        if reminder.calendar == nil {
            throw EventKitError.saveFailed("no default reminder list available; specify --list")
        }
        if let notes { reminder.notes = notes }
        if let due { reminder.dueDateComponents = EventKitDate.dueComponents(from: due) }
        if let priority { reminder.priority = try Self.priorityValue(priority) }
        try save(reminder)
        log.info("reminder added", metadata: ["id": .string(reminder.calendarItemIdentifier)])
        return ReminderResponse(reminder)
    }

    public func updateReminder(
        id: String, title: String? = nil, list: String? = nil, due: Date? = nil,
        notes: String? = nil, priority: String? = nil, completed: Bool? = nil
    ) async throws -> ReminderResponse {
        log.debug(
            "updateReminder",
            metadata: [
                "id": .string(id), "title": "\(title as Any)", "list": "\(list as Any)",
                "due": "\(due as Any)", "priority": "\(priority as Any)",
                "completed": "\(completed as Any)",
            ])
        try await ensureRemindersAccess()
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw EventKitError.notFound("reminder \(id)")
        }
        if let title { reminder.title = title }
        if let list { reminder.calendar = try reminderCalendar(idOrName: list) }
        if let due { reminder.dueDateComponents = EventKitDate.dueComponents(from: due) }
        if let notes { reminder.notes = notes }
        if let priority { reminder.priority = try Self.priorityValue(priority) }
        if let completed { reminder.isCompleted = completed }
        try save(reminder)
        return ReminderResponse(reminder)
    }

    public func completeReminders(ids: [String]) async throws -> [ReminderResponse] {
        log.info("completeReminders", metadata: ["ids": .string(ids.joined(separator: ","))])
        try await ensureRemindersAccess()
        var result: [ReminderResponse] = []
        for id in ids {
            guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
                throw EventKitError.notFound("reminder \(id)")
            }
            reminder.isCompleted = true
            try save(reminder)
            result.append(ReminderResponse(reminder))
        }
        return result
    }

    public func deleteReminders(ids: [String]) async throws {
        log.info("deleteReminders", metadata: ["ids": .string(ids.joined(separator: ","))])
        try await ensureRemindersAccess()
        for id in ids {
            guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
                throw EventKitError.notFound("reminder \(id)")
            }
            do {
                try store.remove(reminder, commit: true)
            } catch {
                throw EventKitError.removeFailed(error.localizedDescription)
            }
        }
    }

    // MARK: - Events

    public func fetchEvents(start: Date, end: Date, calendar: String? = nil) async throws -> [EventResponse] {
        log.debug(
            "fetchEvents",
            metadata: ["start": "\(start)", "end": "\(end)", "calendar": .string(calendar ?? "*")])
        try await ensureEventsAccess()
        let calendars = try calendar.map { try [eventCalendar(idOrName: $0)] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let result = store.events(matching: predicate)
            .map(EventResponse.init)
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        log.debug("fetchEvents result", metadata: ["count": "\(result.count)"])
        return result
    }

    public func addEvent(
        title: String, calendar: String? = nil, start: Date, end: Date, isAllDay: Bool = false,
        notes: String? = nil, location: String? = nil, url: String? = nil
    ) async throws -> EventResponse {
        log.debug(
            "addEvent",
            metadata: [
                "title": .string(title), "calendar": .string(calendar ?? "<default>"),
                "start": "\(start)", "end": "\(end)", "allDay": "\(isAllDay)",
            ])
        try await ensureEventsAccess()
        let event = EKEvent(eventStore: store)
        event.title = title
        event.calendar = try calendar.map { try eventCalendar(idOrName: $0) }
            ?? store.defaultCalendarForNewEvents
        if event.calendar == nil {
            throw EventKitError.saveFailed("no default calendar available; specify --calendar")
        }
        event.startDate = start
        event.endDate = end
        event.isAllDay = isAllDay
        if let notes { event.notes = notes }
        if let location { event.location = location }
        if let url { event.url = URL(string: url) }
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw EventKitError.saveFailed(error.localizedDescription)
        }
        log.info("event added", metadata: ["id": .string(event.eventIdentifier ?? "")])
        return EventResponse(event)
    }

    public func updateEvent(
        id: String, title: String? = nil, calendar: String? = nil, start: Date? = nil,
        end: Date? = nil, isAllDay: Bool? = nil, notes: String? = nil, location: String? = nil,
        url: String? = nil
    ) async throws -> EventResponse {
        log.debug("updateEvent", metadata: ["id": .string(id)])
        try await ensureEventsAccess()
        guard let event = store.event(withIdentifier: id) else {
            throw EventKitError.notFound("event \(id)")
        }
        if let title { event.title = title }
        if let calendar { event.calendar = try eventCalendar(idOrName: calendar) }
        if let start { event.startDate = start }
        if let end { event.endDate = end }
        if let isAllDay { event.isAllDay = isAllDay }
        if let notes { event.notes = notes }
        if let location { event.location = location }
        if let url { event.url = URL(string: url) }
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw EventKitError.saveFailed(error.localizedDescription)
        }
        return EventResponse(event)
    }

    public func deleteEvents(ids: [String]) async throws {
        log.info("deleteEvents", metadata: ["ids": .string(ids.joined(separator: ","))])
        try await ensureEventsAccess()
        for id in ids {
            guard let event = store.event(withIdentifier: id) else {
                throw EventKitError.notFound("event \(id)")
            }
            do {
                try store.remove(event, span: .thisEvent, commit: true)
            } catch {
                throw EventKitError.removeFailed(error.localizedDescription)
            }
        }
    }

    // MARK: - Helpers

    private func save(_ reminder: EKReminder) throws {
        do {
            try store.save(reminder, commit: true)
        } catch {
            throw EventKitError.saveFailed(error.localizedDescription)
        }
    }

    private func fetchReminderResponses(matching predicate: NSPredicate) async -> [ReminderResponse] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(ReminderResponse.init))
            }
        }
    }

    private func reminderCalendar(idOrName: String) throws -> EKCalendar {
        try calendar(idOrName: idOrName, entity: .reminder, label: "reminder list")
    }

    private func eventCalendar(idOrName: String) throws -> EKCalendar {
        try calendar(idOrName: idOrName, entity: .event, label: "calendar")
    }

    private func calendar(idOrName: String, entity: EKEntityType, label: String) throws -> EKCalendar {
        let calendars = store.calendars(for: entity)
        if let byId = calendars.first(where: { $0.calendarIdentifier == idOrName }) {
            return byId
        }
        if let byName = calendars.first(where: { $0.title == idOrName }) {
            return byName
        }
        throw EventKitError.notFound("\(label) '\(idOrName)'")
    }

    private static func priorityValue(_ string: String) throws -> Int {
        guard let priority = ReminderPriority(string: string) else {
            throw EventKitError.invalidArgument(
                "priority must be one of: \(ReminderPriority.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        return priority.ekValue
    }

    private static func reminderOrder(_ a: ReminderResponse, _ b: ReminderResponse) -> Bool {
        switch (a.dueDate, b.dueDate) {
        case let (x?, y?) where x != y:
            return x < y
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        default:
            return a.title.localizedCompare(b.title) == .orderedAscending
        }
    }
}
