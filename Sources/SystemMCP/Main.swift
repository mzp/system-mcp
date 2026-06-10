import ArgumentParser
import SystemMCPCore
import Foundation

@main
struct SystemMCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "systemmcp",
        abstract: "Control macOS Reminders & Calendar via EventKit, as a CLI or MCP servers.",
        version: "0.1.0",
        subcommands: [
            ReminderCommand.self,
            CalendarCommand.self,
        ]
    )
}

/// Shared accessor for the EventKit service. A single actor instance serves both domains.
let service = EventKitService()
