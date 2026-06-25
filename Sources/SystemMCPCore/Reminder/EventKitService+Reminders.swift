import CoreLocation
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

extension EventKitService {

    // MARK: - Reminder lists

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

    /// Creates a reminder list. By default a list whose title already exists is refused, so a
    /// caller that hit a resolve failure doesn't accidentally create a duplicate (which then
    /// makes the name ambiguous). Pass `force: true` to create a same-named list anyway — only
    /// after explicit user confirmation, since duplicates are usually a mistake.
    public func createReminderList(name: String, force: Bool = false) async throws -> CalendarResponse {
        log.debug("createReminderList", metadata: ["name": .string(name), "force": "\(force)"])
        try await ensureRemindersAccess()
        if !force {
            let existing = store.calendars(for: .reminder).filter { $0.title == name }
            if !existing.isEmpty {
                throw EventKitError.invalidArgument(
                    "a reminder list named '\(name)' already exists (id: "
                        + existing.map(\.calendarIdentifier).joined(separator: ", ")
                        + "). Use the existing list, or pass force to create a duplicate "
                        + "(only with the user's explicit confirmation)")
            }
        }
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
                guard let due = reminder.dueDate?.date else { return false }
                return calendar.isDate(due, inSameDayAs: now)
            case .tomorrow:
                guard let due = reminder.dueDate?.date,
                    let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)
                else { return false }
                return calendar.isDate(due, inSameDayAs: tomorrow)
            case .week:
                guard let due = reminder.dueDate?.date,
                    let weekEnd = calendar.date(byAdding: .day, value: 7, to: startOfToday)
                else { return false }
                return due >= startOfToday && due < weekEnd
            case .overdue:
                guard let due = reminder.dueDate?.date else { return false }
                return due < now
            case .upcoming:
                guard let due = reminder.dueDate?.date else { return false }
                return due >= now
            case .range(let start, let end):
                guard let due = reminder.dueDate?.date else { return false }
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
        priority: String? = nil, location: String? = nil, proximity: String? = nil,
        radius: Double? = nil, anchor: TimeAnchor = .local
    ) async throws -> ReminderResponse {
        log.debug(
            "addReminder",
            metadata: [
                "title": .string(title), "list": .string(list ?? "<default>"),
                "due": "\(due as Any)", "priority": .string(priority ?? "none"),
                "location": .string(location ?? "<none>"),
                "anchor": "\(anchor)",
            ])
        try await ensureRemindersAccess()
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar =
            try list.map { try reminderCalendar(idOrName: $0) }
            ?? store.defaultCalendarForNewReminders()
        if reminder.calendar == nil {
            throw EventKitError.saveFailed("no default reminder list available; specify --list")
        }
        if let notes { reminder.notes = notes }
        if let due { reminder.dueDateComponents = DateParsing.dueComponents(from: due, timeZone: anchor.dueZone) }
        if let priority { reminder.priority = try Self.priorityValue(priority) }
        try await setLocationAlarm(on: reminder, location: location, proximity: proximity, radius: radius)
        try save(reminder)
        log.info("reminder added", metadata: ["id": .string(reminder.calendarItemIdentifier)])
        return ReminderResponse(reminder)
    }

    public func updateReminder(
        id: String, title: String? = nil, due: Date? = nil,
        notes: String? = nil, priority: String? = nil, completed: Bool? = nil,
        location: String? = nil, proximity: String? = nil, radius: Double? = nil,
        anchor: TimeAnchor = .local
    ) async throws -> ReminderResponse {
        log.debug(
            "updateReminder",
            metadata: [
                "id": .string(id), "title": "\(title as Any)",
                "due": "\(due as Any)", "priority": "\(priority as Any)",
                "completed": "\(completed as Any)", "location": "\(location as Any)",
            ])
        try await ensureRemindersAccess()
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw EventKitError.notFound("reminder \(id)")
        }
        if let title { reminder.title = title }
        if let due { reminder.dueDateComponents = DateParsing.dueComponents(from: due, timeZone: anchor.dueZone) }
        if let notes { reminder.notes = notes }
        if let priority { reminder.priority = try Self.priorityValue(priority) }
        if let completed { reminder.isCompleted = completed }
        try await setLocationAlarm(on: reminder, location: location, proximity: proximity, radius: radius)
        try save(reminder)
        return ReminderResponse(reminder)
    }

    /// Moves a reminder to another list. Tries an in-place `calendar` reassignment first
    /// (lossless, keeps the id; this is the path that works within one account). When EventKit
    /// refuses the move — notably for a shared list, where reassigning `calendar` fails with
    /// reminderkit error -3002 even though the list is in the same account and writable — it
    /// falls back to recreating the reminder in the destination and deleting the original.
    /// The recreate path changes the reminder's id. See docs/eventkit.md.
    public func moveReminder(id: String, list: String) async throws -> ReminderResponse {
        log.debug("moveReminder", metadata: ["id": .string(id), "list": .string(list)])
        try await ensureRemindersAccess()
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw EventKitError.notFound("reminder \(id)")
        }
        let destination = try reminderCalendar(idOrName: list)
        if reminder.calendar?.calendarIdentifier == destination.calendarIdentifier {
            return ReminderResponse(reminder)
        }
        guard destination.allowsContentModifications else {
            throw EventKitError.invalidArgument(
                "cannot move reminder into list '\(destination.title)': the list is read-only "
                    + "(e.g. a shared list you do not have permission to edit)")
        }
        do {
            let detachedAlarms = detachLocationAlarms(from: reminder)
            reminder.calendar = destination
            try store.save(reminder, commit: true)
            if !detachedAlarms.isEmpty {
                for alarm in detachedAlarms { reminder.addAlarm(alarm) }
                try store.save(reminder, commit: true)
            }
            log.info("reminder moved in place", metadata: ["id": .string(reminder.calendarItemIdentifier)])
            return ReminderResponse(reminder)
        } catch {
            // EventKit rejected the in-place move (e.g. destination is a shared list). Discard
            // the uncommitted mutations and move by recreate-then-delete instead.
            log.warning(
                "in-place move rejected; recreating in destination",
                metadata: ["id": .string(id), "error": "\(error)"])
            store.reset()
            return try recreateForMove(originalId: id, into: list)
        }
    }

    /// Performs a move by creating a fresh copy in the destination list, then deleting the
    /// original. The copy is saved *before* the original is removed, so a failure to create
    /// (e.g. EventKit also refuses writes to the destination) never loses the original.
    private func recreateForMove(originalId: String, into list: String) throws -> ReminderResponse {
        guard let original = store.calendarItem(withIdentifier: originalId) as? EKReminder else {
            throw EventKitError.notFound("reminder \(originalId)")
        }
        let destination = try reminderCalendar(idOrName: list)
        let copy = EKReminder(eventStore: store)
        copy.calendar = destination
        copy.title = original.title
        copy.notes = original.notes
        copy.priority = original.priority
        copy.dueDateComponents = original.dueDateComponents
        copy.startDateComponents = original.startDateComponents
        copy.isCompleted = original.isCompleted
        if let url = original.url { copy.url = url }
        for alarm in original.alarms ?? [] { copy.addAlarm(Self.clone(alarm)) }
        do {
            try store.save(copy, commit: true)
        } catch {
            throw EventKitError.saveFailed(
                "could not move reminder into list '\(destination.title)' by recreating it "
                    + "(\(error.localizedDescription)); the original was left untouched")
        }
        do {
            try store.remove(original, commit: true)
        } catch {
            throw EventKitError.removeFailed(
                "recreated the reminder in '\(destination.title)' (new id \(copy.calendarItemIdentifier)), "
                    + "but could not delete the original \(originalId): \(error.localizedDescription). "
                    + "Delete the original manually to avoid a duplicate")
        }
        log.info(
            "reminder moved by recreate",
            metadata: ["from": .string(originalId), "to": .string(copy.calendarItemIdentifier)])
        return ReminderResponse(copy)
    }

    /// Returns a fresh, equivalent copy of an alarm so it can be attached to another reminder
    /// (the original alarm is bound to its reminder/source). Handles location, absolute-date,
    /// and relative-offset alarms.
    private static func clone(_ alarm: EKAlarm) -> EKAlarm {
        if let location = alarm.structuredLocation {
            let structured = EKStructuredLocation(title: location.title ?? "")
            structured.geoLocation = location.geoLocation
            structured.radius = location.radius
            let copy = EKAlarm()
            copy.structuredLocation = structured
            copy.proximity = alarm.proximity
            return copy
        }
        if let absoluteDate = alarm.absoluteDate {
            return EKAlarm(absoluteDate: absoluteDate)
        }
        return EKAlarm(relativeOffset: alarm.relativeOffset)
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

    // MARK: - Helpers

    private func ensureRemindersAccess() async throws {
        try await ensureAccess(to: .reminder, label: "reminders")
    }

    private func reminderCalendar(idOrName: String) throws -> EKCalendar {
        try calendar(idOrName: idOrName, entity: .reminder, label: "reminder list")
    }

    private func save(_ reminder: EKReminder) throws {
        do {
            try store.save(reminder, commit: true)
        } catch {
            throw EventKitError.saveFailed(error.localizedDescription)
        }
    }

    /// Sets a location-triggered alarm. Unlike event locations, a trigger is useless
    /// without coordinates, so an un-geocodable location is an error here. A new
    /// location replaces any existing location alarms; time-based alarms are kept.
    private func setLocationAlarm(
        on reminder: EKReminder, location: String?, proximity: String?, radius: Double?
    ) async throws {
        guard let location else {
            if proximity != nil || radius != nil {
                throw EventKitError.invalidArgument("proximity/radius require a location")
            }
            return
        }
        guard let proximityValue = AlarmProximity(string: proximity ?? AlarmProximity.enter.rawValue) else {
            throw EventKitError.invalidArgument(
                "proximity must be one of: \(AlarmProximity.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        if let radius, radius <= 0 {
            throw EventKitError.invalidArgument("radius must be a positive number of meters")
        }
        guard let coordinate = await Geocoder.coordinate(for: location) else {
            throw EventKitError.invalidArgument(
                "could not geocode location '\(location)'; a location trigger needs resolvable coordinates")
        }
        let structured = EKStructuredLocation(title: location)
        structured.geoLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if let radius { structured.radius = radius }
        for alarm in reminder.alarms ?? [] where alarm.structuredLocation != nil {
            reminder.removeAlarm(alarm)
        }
        let alarm = EKAlarm()
        alarm.structuredLocation = structured
        alarm.proximity = proximityValue.ekValue
        reminder.addAlarm(alarm)
    }

    /// Removes the reminder's location alarms and returns fresh, equivalent copies. Used by
    /// `moveReminder` to carry a geofence across a list (source) change: the original alarm
    /// is bound to the old source, so it must be detached before the move and re-added after.
    private func detachLocationAlarms(from reminder: EKReminder) -> [EKAlarm] {
        var detached: [EKAlarm] = []
        for alarm in reminder.alarms ?? [] {
            guard let existing = alarm.structuredLocation else { continue }
            let structured = EKStructuredLocation(title: existing.title ?? "")
            structured.geoLocation = existing.geoLocation
            structured.radius = existing.radius
            let copy = EKAlarm()
            copy.structuredLocation = structured
            copy.proximity = alarm.proximity
            detached.append(copy)
            reminder.removeAlarm(alarm)
        }
        return detached
    }

    private func fetchReminderResponses(matching predicate: NSPredicate) async -> [ReminderResponse] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(ReminderResponse.init))
            }
        }
    }

    private static func priorityValue(_ string: String) throws -> Int {
        guard let priority = ReminderPriority(string: string) else {
            throw EventKitError.invalidArgument(
                "priority must be one of: \(ReminderPriority.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        return priority.ekValue
    }

    private static func reminderOrder(_ a: ReminderResponse, _ b: ReminderResponse) -> Bool {
        switch (a.dueDate?.date, b.dueDate?.date) {
        case (let x?, let y?) where x != y:
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
