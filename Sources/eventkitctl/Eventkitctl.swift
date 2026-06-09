import ArgumentParser
import AppCore
import Foundation

@main
struct Eventkitctl: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "eventkitctl",
        abstract: "Control macOS Calendar & Reminders via EventKit, as a CLI or an MCP server.",
        version: "0.1.0",
        subcommands: [
            StatusCommand.self,
            RemindersCommand.self,
            ListsCommand.self,
            EventsCommand.self,
            CalendarsCommand.self,
            ServeCommand.self,
        ]
    )
}

/// Output helpers shared by all CLI subcommands.
enum Output {
    static func json<T: Encodable>(_ value: T) {
        do {
            let data = try EventKitDate.jsonEncoder.encode(value)
            if let string = String(data: data, encoding: .utf8) {
                print(string)
            }
        } catch {
            FileHandle.standardError.write(Data("encoding error: \(error)\n".utf8))
        }
    }
}

/// Shared accessor for the EventKit service.
let service = EventStoreService()
