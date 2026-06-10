import ArgumentParser
import SystemMCPCore
import Foundation

struct ReminderStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show Reminders authorization status; triggers the permission prompt on first run."
    )

    func run() async throws {
        let status = await service.requestAccess(to: .reminder)
        Output.json(status)
    }
}
