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
                "start": string("Range start, ISO8601, today/tomorrow, or relative (+1h, +30m) (overrides filter)"),
                "end": string("Range end, ISO8601, today/tomorrow, or relative (+1h, +30m) (overrides filter)"),
            ])),
        Tool(
            name: "add_reminder",
            description: "Create a reminder.",
            inputSchema: object(
                [
                    "title": string("Reminder title"),
                    "list": string("Reminder list name or id (default list if omitted)"),
                    "due": string(
                        "Due date, ISO8601 (2026-06-10T10:00), today/tomorrow, or relative (+1h, +30m, +1h30m)"),
                    "timezone": string(
                        "Time zone for the due date (IANA name like America/New_York, or EST). Omit to fix the due date to the device's local zone; pass a zone to fix it to that zone's absolute moment; pass 'floating' for a zone-less reminder that fires at this wall-clock time wherever the device is."
                    ),
                    "notes": string("Notes"),
                    "priority": string("none | low | medium | high"),
                    "location": string(
                        "Location trigger (address or place name; geocoded, must resolve to coordinates)"),
                    "proximity": string("Location trigger timing: enter (arrive) | leave (depart); default enter"),
                    "radius": number("Location trigger radius in meters (system default if omitted)"),
                ], required: ["title"])),
        Tool(
            name: "update_reminder",
            description: "Update a reminder by id. Only provided fields change. To change list, use move_reminder.",
            inputSchema: object(
                [
                    "id": string("Reminder id (calendarItemIdentifier)"),
                    "title": string("New title"),
                    "due": string("New due date, ISO8601, today/tomorrow, or relative (+1h, +30m, +1h30m)"),
                    "timezone": string(
                        "Time zone for the due date (IANA name like America/New_York, or EST). Omit to fix the due date to the device's local zone; pass a zone to fix it to that zone's absolute moment; pass 'floating' for a zone-less reminder that fires at this wall-clock time wherever the device is."
                    ),
                    "notes": string("New notes"),
                    "priority": string("none | low | medium | high"),
                    "completed": bool("Mark completed or not"),
                    "location": string(
                        "New location trigger (replaces the existing one; geocoded, must resolve to coordinates)"),
                    "proximity": string("Location trigger timing: enter (arrive) | leave (depart); default enter"),
                    "radius": number("Location trigger radius in meters (system default if omitted)"),
                ], required: ["id"])),
        Tool(
            name: "move_reminder",
            description:
                "Move a reminder to another list (name or id). Preserves location triggers and other attributes. Moving into a shared list is done by recreating the reminder there and deleting the original, so the reminder's id changes in that case.",
            inputSchema: object(
                [
                    "id": string("Reminder id (calendarItemIdentifier)"),
                    "list": string("Destination list name or id"),
                ], required: ["id", "list"])),
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
            description:
                "Create a reminder list. Fails if a list with the same name already exists, unless force is true. Do NOT set force on your own to work around a failed lookup: a duplicate name is almost always a mistake. Only pass force after the user has explicitly confirmed they want a second list with that name.",
            inputSchema: object(
                [
                    "name": string("New list name"),
                    "force": bool(
                        "Create even if a same-named list exists. Requires the user's explicit confirmation; do not set it to bypass an error."
                    ),
                ], required: ["name"])),
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
                let anchor = try parseAnchorOrThrow(args.str("timezone"))
                let due = try args.str("due").map { try parseDateOrThrow($0, field: "due", timeZone: anchor.parseZone) }
                return jsonResult(
                    try await service.addReminder(
                        title: title, list: args.str("list"), due: due, notes: args.str("notes"),
                        priority: args.str("priority"), location: args.str("location"),
                        proximity: args.str("proximity"), radius: args.double("radius"), anchor: anchor))

            case "update_reminder":
                guard let id = args.str("id") else { return missing("id") }
                let anchor = try parseAnchorOrThrow(args.str("timezone"))
                let due = try args.str("due").map { try parseDateOrThrow($0, field: "due", timeZone: anchor.parseZone) }
                return jsonResult(
                    try await service.updateReminder(
                        id: id, title: args.str("title"), due: due,
                        notes: args.str("notes"), priority: args.str("priority"),
                        completed: args.bool("completed"), location: args.str("location"),
                        proximity: args.str("proximity"), radius: args.double("radius"), anchor: anchor))

            case "move_reminder":
                guard let id = args.str("id") else { return missing("id") }
                guard let list = args.str("list") else { return missing("list") }
                return jsonResult(try await service.moveReminder(id: id, list: list))

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
                return jsonResult(try await service.createReminderList(name: name, force: args.bool("force") ?? false))

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
