import ArgumentParser
import Foundation
import MCP
import SystemMCPCore

struct ReminderServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Run the Reminders MCP server over stdio (for Claude Desktop and other MCP clients)."
    )

    func run() async throws {
        let server = Server(
            name: "apple-reminder",
            version: "0.1.0",
            capabilities: .init(tools: .init(listChanged: false))
        )

        _ = await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: ReminderMCP.tools)
        }

        _ = await server.withMethodHandler(CallTool.self) { params in
            await ReminderMCP.handle(name: params.name, arguments: params.arguments)
        }

        // Pass our stderr logger to the transport too, so protocol-level diagnostics
        // (visible with SYSTEM_MCP_LOG=debug) never touch stdout.
        let transport = StdioTransport(logger: log)
        log.info("MCP server starting", metadata: ["server": "apple-reminder", "tools": "\(ReminderMCP.tools.count)"])
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
        log.info("MCP server stopped")
    }
}
