import AppCore
import Foundation
import MCP

// MARK: - Schema builders

private func object(_ properties: [String: Value], required: [String] = []) -> Value {
    .object([
        "type": .string("object"),
        "properties": .object(properties),
        "required": .array(required.map { .string($0) }),
    ])
}

private func string(_ description: String) -> Value {
    .object(["type": .string("string"), "description": .string(description)])
}

private func bool(_ description: String) -> Value {
    .object(["type": .string("boolean"), "description": .string(description)])
}

private func stringArray(_ description: String) -> Value {
    .object([
        "type": .string("array"),
        "description": .string(description),
        "items": .object(["type": .string("string")]),
    ])
}

// MARK: - Tool list

let allTools: [Tool] = [
    Tool(
        name: "get_status",
        description: "Show EventKit authorization status for calendar events and reminders.",
        inputSchema: object([:])),

    // Reminders
    Tool(
        name: "list_reminders",
        description:
            "List reminders. Use `filter` (today, tomorrow, week, overdue, upcoming, completed, all) or a `start`/`end` date range. Optionally restrict to one `list`.",
        inputSchema: object([
            "filter": string("today | tomorrow | week | overdue | upcoming | completed | all (default all)"),
            "list": string("Reminder list name or id"),
            "start": string("Range start, ISO8601 or today/tomorrow (overrides filter)"),
            "end": string("Range end, ISO8601 or today/tomorrow (overrides filter)"),
        ])),
    Tool(
        name: "add_reminder",
        description: "Create a reminder.",
        inputSchema: object([
            "title": string("Reminder title"),
            "list": string("Reminder list name or id (default list if omitted)"),
            "due": string("Due date, ISO8601 (2026-06-10T10:00) or today/tomorrow"),
            "notes": string("Notes"),
            "priority": string("none | low | medium | high"),
        ], required: ["title"])),
    Tool(
        name: "update_reminder",
        description: "Update a reminder by id. Only provided fields change.",
        inputSchema: object([
            "id": string("Reminder id (calendarItemIdentifier)"),
            "title": string("New title"),
            "list": string("Move to list (name or id)"),
            "due": string("New due date, ISO8601 or today/tomorrow"),
            "notes": string("New notes"),
            "priority": string("none | low | medium | high"),
            "completed": bool("Mark completed or not"),
        ], required: ["id"])),
    Tool(
        name: "complete_reminders",
        description: "Mark one or more reminders completed.",
        inputSchema: object([
            "ids": stringArray("Reminder ids")
        ], required: ["ids"])),
    Tool(
        name: "delete_reminders",
        description: "Delete one or more reminders.",
        inputSchema: object([
            "ids": stringArray("Reminder ids")
        ], required: ["ids"])),

    // Reminder lists
    Tool(
        name: "list_reminder_lists",
        description: "List all reminder lists.",
        inputSchema: object([:])),
    Tool(
        name: "create_reminder_list",
        description: "Create a reminder list.",
        inputSchema: object(["name": string("New list name")], required: ["name"])),
    Tool(
        name: "rename_reminder_list",
        description: "Rename a reminder list.",
        inputSchema: object([
            "list": string("Existing list name or id"),
            "newName": string("New name"),
        ], required: ["list", "newName"])),
    Tool(
        name: "delete_reminder_list",
        description: "Delete a reminder list and its contents.",
        inputSchema: object(["list": string("List name or id")], required: ["list"])),

    // Calendars
    Tool(
        name: "list_calendars",
        description: "List all calendars.",
        inputSchema: object([:])),

    // Events
    Tool(
        name: "list_events",
        description: "List calendar events within a date range.",
        inputSchema: object([
            "start": string("Range start, ISO8601 or today/tomorrow"),
            "end": string("Range end, ISO8601 or today/tomorrow"),
            "calendar": string("Restrict to a calendar (name or id)"),
        ], required: ["start", "end"])),
    Tool(
        name: "add_event",
        description: "Create a calendar event.",
        inputSchema: object([
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
        inputSchema: object([
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
        inputSchema: object([
            "ids": stringArray("Event ids")
        ], required: ["ids"])),
]

// MARK: - Argument access

extension Optional where Wrapped == [String: Value] {
    func str(_ key: String) -> String? { self?[key]?.stringValue }
    func bool(_ key: String) -> Bool? { self?[key]?.boolValue }
    func strArray(_ key: String) -> [String]? {
        self?[key]?.arrayValue?.compactMap { $0.stringValue }
    }
}

// MARK: - Result helpers

private func jsonResult<T: Encodable>(_ value: T) -> CallTool.Result {
    do {
        let data = try EventKitDate.jsonEncoder.encode(value)
        return CallTool.Result(
            content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)])
    } catch {
        return errorResult("encoding failed: \(error)")
    }
}

private func errorResult(_ message: String) -> CallTool.Result {
    CallTool.Result(
        content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
}

private func missing(_ field: String) -> CallTool.Result {
    errorResult("missing required argument: \(field)")
}

// MARK: - Dispatch

func handleToolCall(name: String, arguments args: [String: Value]?) async -> CallTool.Result {
    do {
        switch name {
        case "get_status":
            return jsonResult(await service.requestAccess())

        // Reminders
        case "list_reminders":
            let filter = try resolveFilter(
                filter: args.str("filter") ?? "all", start: args.str("start"), end: args.str("end"))
            return jsonResult(try await service.fetchReminders(filter: filter, list: args.str("list")))

        case "add_reminder":
            guard let title = args.str("title") else { return missing("title") }
            let due = try args.str("due").map { try parseDateOrThrow($0, field: "due") }
            return jsonResult(
                try await service.addReminder(
                    title: title, list: args.str("list"), due: due, notes: args.str("notes"),
                    priority: args.str("priority")))

        case "update_reminder":
            guard let id = args.str("id") else { return missing("id") }
            let due = try args.str("due").map { try parseDateOrThrow($0, field: "due") }
            return jsonResult(
                try await service.updateReminder(
                    id: id, title: args.str("title"), list: args.str("list"), due: due,
                    notes: args.str("notes"), priority: args.str("priority"),
                    completed: args.bool("completed")))

        case "complete_reminders":
            guard let ids = args.strArray("ids") else { return missing("ids") }
            return jsonResult(try await service.completeReminders(ids: ids))

        case "delete_reminders":
            guard let ids = args.strArray("ids") else { return missing("ids") }
            try await service.deleteReminders(ids: ids)
            return jsonResult(["deleted": ids])

        // Reminder lists
        case "list_reminder_lists":
            return jsonResult(try await service.listReminderLists())

        case "create_reminder_list":
            guard let name = args.str("name") else { return missing("name") }
            return jsonResult(try await service.createReminderList(name: name))

        case "rename_reminder_list":
            guard let list = args.str("list") else { return missing("list") }
            guard let newName = args.str("newName") else { return missing("newName") }
            return jsonResult(try await service.renameReminderList(idOrName: list, newName: newName))

        case "delete_reminder_list":
            guard let list = args.str("list") else { return missing("list") }
            try await service.deleteReminderList(idOrName: list)
            return jsonResult(["deleted": list])

        // Calendars
        case "list_calendars":
            return jsonResult(try await service.listCalendars())

        // Events
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
        return errorResult(error.description)
    } catch {
        return errorResult(error.localizedDescription)
    }
}
