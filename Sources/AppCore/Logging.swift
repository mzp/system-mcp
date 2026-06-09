import Foundation
import Logging

/// Shared logger for both the CLI and the MCP server.
///
/// IMPORTANT: logs go to **stderr**, never stdout. In `serve` mode stdout is reserved
/// for the MCP protocol, and on the CLI stdout carries the JSON result — so logging on
/// stderr keeps both clean while staying visible for debugging (`ek ... 2> log.txt`,
/// or captured by Claude Desktop's MCP logs).
///
/// Level is controlled by the `EVENTKITCTL_LOG` env var:
///   trace | debug | info | notice | warning | error | critical
/// Default is `info`, so routine per-call parameter logging (emitted at `debug`) is
/// silent until you opt in with `EVENTKITCTL_LOG=debug`.
public let log: Logger = {
    var logger = Logger(label: "eventkitctl") { label in
        StreamLogHandler.standardError(label: label)
    }
    logger.logLevel = levelFromEnvironment()
    return logger
}()

private func levelFromEnvironment() -> Logger.Level {
    guard let raw = ProcessInfo.processInfo.environment["EVENTKITCTL_LOG"],
        let level = Logger.Level(rawValue: raw.lowercased())
    else {
        return .info
    }
    return level
}
