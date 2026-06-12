import ArgumentParser
import Foundation
import SystemMCPCore

struct EventsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "events",
        abstract: "List and manage calendar events.",
        subcommands: [List.self, Add.self, Update.self, Delete.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List events in a date range.")

        @Option(help: "Range start (ISO8601 or today/tomorrow).") var start: String
        @Option(help: "Range end (ISO8601 or today/tomorrow).") var end: String
        @Option(help: "Restrict to a calendar (name or id).") var calendar: String?
        @Option(help: "Time zone for interpreting start/end (IANA name like America/New_York, or EST).")
        var timezone: String?

        func run() async throws {
            let zone = try timezone.map(parseTimeZoneOrThrow) ?? .current
            let startDate = try parseDateOrThrow(start, field: "start", timeZone: zone)
            let endDate = try parseDateOrThrow(end, field: "end", timeZone: zone)
            let events = try await service.fetchEvents(
                start: startDate, end: endDate, calendar: calendar)
            Output.json(events)
        }
    }

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Add a calendar event.")

        @Option(help: "Event title.") var title: String
        @Option(help: "Calendar (name or id).") var calendar: String?
        @Option(help: "Start (ISO8601 or today/tomorrow).") var start: String
        @Option(help: "End (ISO8601 or today/tomorrow).") var end: String
        @Flag(help: "All-day event.") var allDay: Bool = false
        @Option(help: "Notes.") var notes: String?
        @Option(help: "Location (address or place name; geocoded to map coordinates when resolvable).")
        var location: String?
        @Option(help: "URL.") var url: String?
        @Option(
            help: """
                Time zone of the event (IANA name like America/New_York, or EST). \
                Start/end without an explicit offset are interpreted in this zone.
                """)
        var timezone: String?

        func run() async throws {
            let zone = try timezone.map(parseTimeZoneOrThrow)
            let startDate = try parseDateOrThrow(start, field: "start", timeZone: zone ?? .current)
            let endDate = try parseDateOrThrow(end, field: "end", timeZone: zone ?? .current)
            let event = try await service.addEvent(
                title: title, calendar: calendar, start: startDate, end: endDate,
                isAllDay: allDay, notes: notes, location: location, url: url, timeZone: zone)
            Output.json(event)
        }
    }

    struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Update an event by id.")

        @Argument(help: "Event id (eventIdentifier).") var id: String
        @Option(help: "New title.") var title: String?
        @Option(help: "Move to calendar (name or id).") var calendar: String?
        @Option(help: "New start (ISO8601 or today/tomorrow).") var start: String?
        @Option(help: "New end (ISO8601 or today/tomorrow).") var end: String?
        @Flag(inversion: .prefixedNo, help: "All-day event.") var allDay: Bool?
        @Option(help: "New notes.") var notes: String?
        @Option(help: "New location (address or place name; geocoded to map coordinates when resolvable).")
        var location: String?
        @Option(help: "New URL.") var url: String?
        @Option(
            help: """
                New time zone of the event (IANA name like America/New_York, or EST). \
                Start/end without an explicit offset are interpreted in this zone.
                """)
        var timezone: String?

        func run() async throws {
            let zone = try timezone.map(parseTimeZoneOrThrow)
            let startDate = try start.map { try parseDateOrThrow($0, field: "start", timeZone: zone ?? .current) }
            let endDate = try end.map { try parseDateOrThrow($0, field: "end", timeZone: zone ?? .current) }
            let event = try await service.updateEvent(
                id: id, title: title, calendar: calendar, start: startDate, end: endDate,
                isAllDay: allDay, notes: notes, location: location, url: url, timeZone: zone)
            Output.json(event)
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete events.")
        @Argument(help: "Event ids.") var ids: [String]

        func run() async throws {
            try await service.deleteEvents(ids: ids)
            Output.json(["deleted": ids])
        }
    }
}
