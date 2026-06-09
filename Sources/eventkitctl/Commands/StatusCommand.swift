import ArgumentParser
import AppCore
import Foundation

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show EventKit authorization status; triggers the permission prompt on first run."
    )

    func run() async throws {
        let status = await service.requestAccess()
        Output.json(status)
    }
}
