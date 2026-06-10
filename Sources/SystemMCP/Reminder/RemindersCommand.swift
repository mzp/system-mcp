import ArgumentParser
import Foundation
import SystemMCPCore

struct RemindersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminders",
        abstract: "List and manage reminders.",
        subcommands: [List.self, Add.self, Update.self, Complete.self, Delete.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List reminders by filter (today/tomorrow/week/overdue/upcoming/completed/all) or a date range.")

        @Option(help: "Filter preset. Default: all.")
        var filter: String = "all"

        @Option(help: "Restrict to a reminder list (name or id).")
        var list: String?

        @Option(help: "Range start (ISO8601 or today/tomorrow). Overrides --filter.")
        var start: String?

        @Option(help: "Range end (ISO8601 or today/tomorrow). Overrides --filter.")
        var end: String?

        func run() async throws {
            let resolved = try resolveFilter(filter: filter, start: start, end: end)
            let reminders = try await service.fetchReminders(filter: resolved, list: list)
            Output.json(reminders)
        }
    }

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Add a reminder.")

        @Option(help: "Reminder title.") var title: String
        @Option(help: "Reminder list (name or id).") var list: String?
        @Option(help: "Due date (ISO8601 or today/tomorrow).") var due: String?
        @Option(help: "Notes.") var notes: String?
        @Option(help: "Priority: none/low/medium/high.") var priority: String?

        func run() async throws {
            let dueDate = try due.map { try parseDateOrThrow($0, field: "due") }
            let reminder = try await service.addReminder(
                title: title, list: list, due: dueDate, notes: notes, priority: priority)
            Output.json(reminder)
        }
    }

    struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Update a reminder by id.")

        @Argument(help: "Reminder id (calendarItemIdentifier).") var id: String
        @Option(help: "New title.") var title: String?
        @Option(help: "Move to list (name or id).") var list: String?
        @Option(help: "New due date (ISO8601 or today/tomorrow).") var due: String?
        @Option(help: "New notes.") var notes: String?
        @Option(help: "Priority: none/low/medium/high.") var priority: String?
        @Flag(inversion: .prefixedNo, help: "Mark completed / not completed.") var completed: Bool?

        func run() async throws {
            let dueDate = try due.map { try parseDateOrThrow($0, field: "due") }
            let reminder = try await service.updateReminder(
                id: id, title: title, list: list, due: dueDate, notes: notes,
                priority: priority, completed: completed)
            Output.json(reminder)
        }
    }

    struct Complete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Mark reminders completed.")
        @Argument(help: "Reminder ids.") var ids: [String]

        func run() async throws {
            let reminders = try await service.completeReminders(ids: ids)
            Output.json(reminders)
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete reminders.")
        @Argument(help: "Reminder ids.") var ids: [String]

        func run() async throws {
            try await service.deleteReminders(ids: ids)
            Output.json(["deleted": ids])
        }
    }
}

/// Resolve a reminder filter from CLI/MCP inputs. `start`/`end` (if present) win over the preset.
func resolveFilter(filter: String, start: String?, end: String?) throws -> ReminderFilter {
    if start != nil || end != nil {
        let startDate = try start.map { try parseDateOrThrow($0, field: "start") }
        let endDate = try end.map { try parseDateOrThrow($0, field: "end") }
        return .range(start: startDate, end: endDate)
    }
    guard let preset = ReminderFilter.named(filter) else {
        throw EventKitError.invalidArgument(
            "unknown filter '\(filter)'. Use today/tomorrow/week/overdue/upcoming/completed/all, or --start/--end.")
    }
    return preset
}
