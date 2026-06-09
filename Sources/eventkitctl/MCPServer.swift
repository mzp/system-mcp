import AppCore
import ArgumentParser
import Foundation
import MCP

struct ServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Run as an MCP server over stdio (for Claude Desktop and other MCP clients)."
    )

    func run() async throws {
        let server = Server(
            name: "eventkitctl",
            version: "0.1.0",
            capabilities: .init(tools: .init(listChanged: false))
        )

        _ = await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: allTools)
        }

        _ = await server.withMethodHandler(CallTool.self) { params in
            await handleToolCall(name: params.name, arguments: params.arguments)
        }

        // Pass our stderr logger to the transport too, so protocol-level diagnostics
        // (visible with EVENTKITCTL_LOG=debug) never touch stdout.
        let transport = StdioTransport(logger: log)
        log.info("MCP server starting", metadata: ["tools": "\(allTools.count)"])
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
        log.info("MCP server stopped")
    }
}
