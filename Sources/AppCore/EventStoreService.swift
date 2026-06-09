import EventKit
import Foundation

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
/// here so the CLI and MCP layers only ever see Sendable DTOs.
public actor EventStoreService {
    private let store = EKEventStore()

    public init() {}

    // MARK: - Authorization

    public func authorizationStatus() -> AuthorizationStatusDTO {
        AuthorizationStatusDTO(
            events: Self.statusName(EKEventStore.authorizationStatus(for: .event)),
            reminders: Self.statusName(EKEventStore.authorizationStatus(for: .reminder)))
    }

    /// Requests access to both entity types (triggers the TCC prompt on first run) and
    /// returns the resulting status.
    @discardableResult
    public func requestAccess() async -> AuthorizationStatusDTO {
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            _ = try? await store.requestFullAccessToEvents()
        }
        if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
            _ = try? await store.requestFullAccessToReminders()
        }
        return authorizationStatus()
    }

    private func ensureRemindersAccess() async throws {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            return
        case .notDetermined:
            let granted = (try? await store.requestFullAccessToReminders()) ?? false
            if !granted { throw EventKitError.accessDenied(entity: "reminders") }
        default:
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

    public func listCalendars() async throws -> [CalendarDTO] {
        try await ensureEventsAccess()
        let defaultId = store.defaultCalendarForNewEvents?.calendarIdentifier
        return store.calendars(for: .event)
            .map { CalendarDTO($0, defaultId: defaultId) }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    public func listReminderLists() async throws -> [CalendarDTO] {
        try await ensureRemindersAccess()
        let defaultId = store.defaultCalendarForNewReminders()?.calendarIdentifier
        return store.calendars(for: .reminder)
            .map { CalendarDTO($0, defaultId: defaultId) }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    public func createReminderList(name: String) async throws -> CalendarDTO {
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
        return CalendarDTO(calendar, defaultId: store.defaultCalendarForNewReminders()?.calendarIdentifier)
    }

    public func renameReminderList(idOrName: String, newName: String) async throws -> CalendarDTO {
        try await ensureRemindersAccess()
        let calendar = try reminderCalendar(idOrName: idOrName)
        calendar.title = newName
        do {
            try store.saveCalendar(calendar, commit: true)
        } catch {
            throw EventKitError.saveFailed(error.localizedDescription)
        }
        return CalendarDTO(calendar, defaultId: store.defaultCalendarForNewReminders()?.calendarIdentifier)
    }

    public func deleteReminderList(idOrName: String) async throws {
        try await ensureRemindersAccess()
        let calendar = try reminderCalendar(idOrName: idOrName)
        do {
            try store.removeCalendar(calendar, commit: true)
        } catch {
            throw EventKitError.removeFailed(error.localizedDescription)
        }
    }

    // MARK: - Reminders

    public func fetchReminders(filter: ReminderFilter, list: String? = nil) async throws -> [ReminderDTO] {
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

        let reminders = await fetchReminderDTOs(matching: predicate)
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

        return filtered.sorted(by: Self.reminderOrder)
    }

    public func addReminder(
        title: String, list: String? = nil, due: Date? = nil, notes: String? = nil,
        priority: String? = nil
    ) async throws -> ReminderDTO {
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
        return ReminderDTO(reminder)
    }

    public func updateReminder(
        id: String, title: String? = nil, list: String? = nil, due: Date? = nil,
        notes: String? = nil, priority: String? = nil, completed: Bool? = nil
    ) async throws -> ReminderDTO {
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
        return ReminderDTO(reminder)
    }

    public func completeReminders(ids: [String]) async throws -> [ReminderDTO] {
        try await ensureRemindersAccess()
        var result: [ReminderDTO] = []
        for id in ids {
            guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
                throw EventKitError.notFound("reminder \(id)")
            }
            reminder.isCompleted = true
            try save(reminder)
            result.append(ReminderDTO(reminder))
        }
        return result
    }

    public func deleteReminders(ids: [String]) async throws {
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

    public func fetchEvents(start: Date, end: Date, calendar: String? = nil) async throws -> [EventDTO] {
        try await ensureEventsAccess()
        let calendars = try calendar.map { try [eventCalendar(idOrName: $0)] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
            .map(EventDTO.init)
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    public func addEvent(
        title: String, calendar: String? = nil, start: Date, end: Date, isAllDay: Bool = false,
        notes: String? = nil, location: String? = nil, url: String? = nil
    ) async throws -> EventDTO {
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
        return EventDTO(event)
    }

    public func updateEvent(
        id: String, title: String? = nil, calendar: String? = nil, start: Date? = nil,
        end: Date? = nil, isAllDay: Bool? = nil, notes: String? = nil, location: String? = nil,
        url: String? = nil
    ) async throws -> EventDTO {
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
        return EventDTO(event)
    }

    public func deleteEvents(ids: [String]) async throws {
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

    private func fetchReminderDTOs(matching predicate: NSPredicate) async -> [ReminderDTO] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(ReminderDTO.init))
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

    private static func reminderOrder(_ a: ReminderDTO, _ b: ReminderDTO) -> Bool {
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
