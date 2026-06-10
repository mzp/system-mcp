import ArgumentParser
import Foundation

/// `systemmcp calendar ...` — Calendar CLI subcommands and the Calendar MCP server.
struct CalendarCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "calendar",
        abstract: "Manage Calendar events and calendars, or run the Calendar MCP server.",
        subcommands: [
            CalendarStatusCommand.self,
            EventsCommand.self,
            CalendarsCommand.self,
            CalendarServeCommand.self,
        ]
    )
}
