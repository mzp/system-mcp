import Foundation
import Logging
import MCP
import SystemMCPCore

/// MCP tool definitions and dispatch for the Reminders server (`systemmcp reminder serve`).
enum ReminderMCP {
    static let tools: [Tool] = [
        Tool(
            name: "get_status",
            description: "Show EventKit authorization status for reminders.",
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
            inputSchema: object(
                [
                    "title": string("Reminder title"),
                    "list": string("Reminder list name or id (default list if omitted)"),
                    "due": string("Due date, ISO8601 (2026-06-10T10:00) or today/tomorrow"),
                    "notes": string("Notes"),
                    "priority": string("none | low | medium | high"),
                    "location": string(
                        "Location trigger (address or place name; geocoded, must resolve to coordinates)"),
                    "proximity": string("Location trigger timing: enter (arrive) | leave (depart); default enter"),
                    "radius": number("Location trigger radius in meters (system default if omitted)"),
                ], required: ["title"])),
        Tool(
            name: "update_reminder",
            description: "Update a reminder by id. Only provided fields change.",
            inputSchema: object(
                [
                    "id": string("Reminder id (calendarItemIdentifier)"),
                    "title": string("New title"),
                    "list": string("Move to list (name or id)"),
                    "due": string("New due date, ISO8601 or today/tomorrow"),
                    "notes": string("New notes"),
                    "priority": string("none | low | medium | high"),
                    "completed": bool("Mark completed or not"),
                    "location": string(
                        "New location trigger (replaces the existing one; geocoded, must resolve to coordinates)"),
                    "proximity": string("Location trigger timing: enter (arrive) | leave (depart); default enter"),
                    "radius": number("Location trigger radius in meters (system default if omitted)"),
                ], required: ["id"])),
        Tool(
            name: "complete_reminders",
            description: "Mark one or more reminders completed.",
            inputSchema: object(
                [
                    "ids": stringArray("Reminder ids")
                ], required: ["ids"])),
        Tool(
            name: "delete_reminders",
            description: "Delete one or more reminders.",
            inputSchema: object(
                [
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
            inputSchema: object(
                [
                    "list": string("Existing list name or id"),
                    "newName": string("New name"),
                ], required: ["list", "newName"])),
        Tool(
            name: "delete_reminder_list",
            description: "Delete a reminder list and its contents.",
            inputSchema: object(["list": string("List name or id")], required: ["list"])),
    ]

    static func handle(name: String, arguments args: [String: Value]?) async -> CallTool.Result {
        log.info("tool call", metadata: ["name": .string(name), "args": "\(args ?? [:])"])
        do {
            switch name {
            case "get_status":
                return jsonResult(await service.requestAccess(to: .reminder))

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
                        priority: args.str("priority"), location: args.str("location"),
                        proximity: args.str("proximity"), radius: args.double("radius")))

            case "update_reminder":
                guard let id = args.str("id") else { return missing("id") }
                let due = try args.str("due").map { try parseDateOrThrow($0, field: "due") }
                return jsonResult(
                    try await service.updateReminder(
                        id: id, title: args.str("title"), list: args.str("list"), due: due,
                        notes: args.str("notes"), priority: args.str("priority"),
                        completed: args.bool("completed"), location: args.str("location"),
                        proximity: args.str("proximity"), radius: args.double("radius")))

            case "complete_reminders":
                guard let ids = args.strArray("ids") else { return missing("ids") }
                return jsonResult(try await service.completeReminders(ids: ids))

            case "delete_reminders":
                guard let ids = args.strArray("ids") else { return missing("ids") }
                try await service.deleteReminders(ids: ids)
                return jsonResult(["deleted": ids])

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
