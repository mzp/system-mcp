import ArgumentParser
import SystemMCPCore
import Foundation

struct CalendarStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show Calendar authorization status; triggers the permission prompt on first run."
    )

    func run() async throws {
        let status = await service.requestAccess(to: .event)
        Output.json(status)
    }
}
