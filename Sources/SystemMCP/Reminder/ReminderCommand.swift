import ArgumentParser
import Foundation

/// `systemmcp reminder ...` — Reminders CLI subcommands and the Reminders MCP server.
struct ReminderCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminder",
        abstract: "Manage Reminders and reminder lists, or run the Reminders MCP server.",
        subcommands: [
            ReminderStatusCommand.self,
            RemindersCommand.self,
            ListsCommand.self,
            ReminderServeCommand.self,
        ]
    )
}
