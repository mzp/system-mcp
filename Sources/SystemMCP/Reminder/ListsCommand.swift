import ArgumentParser
import Foundation
import SystemMCPCore

struct ListsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lists",
        abstract: "Manage reminder lists.",
        subcommands: [List.self, Create.self, Rename.self, Delete.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List all reminder lists.")
        func run() async throws {
            Output.json(try await service.listReminderLists())
        }
    }

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a reminder list.")
        @Argument(help: "New list name.") var name: String
        func run() async throws {
            Output.json(try await service.createReminderList(name: name))
        }
    }

    struct Rename: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Rename a reminder list.")
        @Argument(help: "Existing list (name or id).") var list: String
        @Argument(help: "New name.") var newName: String
        func run() async throws {
            Output.json(try await service.renameReminderList(idOrName: list, newName: newName))
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete a reminder list and its contents.")
        @Argument(help: "List (name or id).") var list: String
        func run() async throws {
            try await service.deleteReminderList(idOrName: list)
            Output.json(["deleted": list])
        }
    }
}
