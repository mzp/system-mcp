import Foundation
import Logging
import MCP
import SystemMCPCore

/// MCP tool definitions and dispatch for the Calendar server (`systemmcp calendar serve`).
enum CalendarMCP {
    static let tools: [Tool] = [
        Tool(
            name: "get_status",
            description: "Show EventKit authorization status for calendar events.",
            inputSchema: object([:])),

        // Calendars
        Tool(
            name: "list_calendars",
            description: "List all calendars.",
            inputSchema: object([:])),

        // Events
        Tool(
            name: "list_events",
            description: "List calendar events within a date range.",
            inputSchema: object(
                [
                    "start": string("Range start, ISO8601 or today/tomorrow"),
                    "end": string("Range end, ISO8601 or today/tomorrow"),
                    "calendar": string("Restrict to a calendar (name or id)"),
                ], required: ["start", "end"])),
        Tool(
            name: "add_event",
            description: "Create a calendar event.",
            inputSchema: object(
                [
                    "title": string("Event title"),
                    "calendar": string("Calendar name or id (default calendar if omitted)"),
                    "start": string("Start, ISO8601 (2026-06-10T10:00) or today/tomorrow"),
                    "end": string("End, ISO8601 or today/tomorrow"),
                    "allDay": bool("All-day event"),
                    "notes": string("Notes"),
                    "location": string("Location"),
                    "url": string("URL"),
                ], required: ["title", "start", "end"])),
        Tool(
            name: "update_event",
            description: "Update an event by id. Only provided fields change.",
            inputSchema: object(
                [
                    "id": string("Event id (eventIdentifier)"),
                    "title": string("New title"),
                    "calendar": string("Move to calendar (name or id)"),
                    "start": string("New start, ISO8601 or today/tomorrow"),
                    "end": string("New end, ISO8601 or today/tomorrow"),
                    "allDay": bool("All-day event"),
                    "notes": string("New notes"),
                    "location": string("New location"),
                    "url": string("New URL"),
                ], required: ["id"])),
        Tool(
            name: "delete_events",
            description: "Delete one or more events.",
            inputSchema: object(
                [
                    "ids": stringArray("Event ids")
                ], required: ["ids"])),
    ]

    static func handle(name: String, arguments args: [String: Value]?) async -> CallTool.Result {
        log.info("tool call", metadata: ["name": .string(name), "args": "\(args ?? [:])"])
        do {
            switch name {
            case "get_status":
                return jsonResult(await service.requestAccess(to: .event))

            case "list_calendars":
                return jsonResult(try await service.listCalendars())

            case "list_events":
                guard let start = args.str("start") else { return missing("start") }
                guard let end = args.str("end") else { return missing("end") }
                return jsonResult(
                    try await service.fetchEvents(
                        start: try parseDateOrThrow(start, field: "start"),
                        end: try parseDateOrThrow(end, field: "end"),
                        calendar: args.str("calendar")))

            case "add_event":
                guard let title = args.str("title") else { return missing("title") }
                guard let start = args.str("start") else { return missing("start") }
                guard let end = args.str("end") else { return missing("end") }
                return jsonResult(
                    try await service.addEvent(
                        title: title, calendar: args.str("calendar"),
                        start: try parseDateOrThrow(start, field: "start"),
                        end: try parseDateOrThrow(end, field: "end"),
                        isAllDay: args.bool("allDay") ?? false, notes: args.str("notes"),
                        location: args.str("location"), url: args.str("url")))

            case "update_event":
                guard let id = args.str("id") else { return missing("id") }
                let start = try args.str("start").map { try parseDateOrThrow($0, field: "start") }
                let end = try args.str("end").map { try parseDateOrThrow($0, field: "end") }
                return jsonResult(
                    try await service.updateEvent(
                        id: id, title: args.str("title"), calendar: args.str("calendar"),
                        start: start, end: end, isAllDay: args.bool("allDay"),
                        notes: args.str("notes"), location: args.str("location"), url: args.str("url")))

            case "delete_events":
                guard let ids = args.strArray("ids") else { return missing("ids") }
                try await service.deleteEvents(ids: ids)
                return jsonResult(["deleted": ids])

            default:
                return errorResult("unknown tool: \(name)")
            }
        } catch let error as EventKitError {
            log.error("tool failed", metadata: ["name": .string(name), "error": .string(error.description)])
            return errorResult(error.description)
        } catch {
            log.error("tool failed", metadata: ["name": .string(name), "error": "\(error)"])
            return errorResult(error.localizedDescription)
        }
    }
}
