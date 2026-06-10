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

        func run() async throws {
            let startDate = try parseDateOrThrow(start, field: "start")
            let endDate = try parseDateOrThrow(end, field: "end")
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
        @Option(help: "Location.") var location: String?
        @Option(help: "URL.") var url: String?

        func run() async throws {
            let startDate = try parseDateOrThrow(start, field: "start")
            let endDate = try parseDateOrThrow(end, field: "end")
            let event = try await service.addEvent(
                title: title, calendar: calendar, start: startDate, end: endDate,
                isAllDay: allDay, notes: notes, location: location, url: url)
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
        @Option(help: "New location.") var location: String?
        @Option(help: "New URL.") var url: String?

        func run() async throws {
            let startDate = try start.map { try parseDateOrThrow($0, field: "start") }
            let endDate = try end.map { try parseDateOrThrow($0, field: "end") }
            let event = try await service.updateEvent(
                id: id, title: title, calendar: calendar, start: startDate, end: endDate,
                isAllDay: allDay, notes: notes, location: location, url: url)
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
