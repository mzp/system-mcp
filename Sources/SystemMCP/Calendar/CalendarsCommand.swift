import ArgumentParser
import Foundation
import SystemMCPCore

struct CalendarsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "calendars",
        abstract: "Manage calendars.",
        subcommands: [List.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List all calendars.")
        func run() async throws {
            Output.json(try await service.listCalendars())
        }
    }
}
