import EventKit
import Foundation

extension EventKitService {

    // MARK: - Calendars

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

    private func ensureEventsAccess() async throws {
        try await ensureAccess(to: .event, label: "calendar events")
    }

    private func eventCalendar(idOrName: String) throws -> EKCalendar {
        try calendar(idOrName: idOrName, entity: .event, label: "calendar")
    }
}
