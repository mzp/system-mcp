import Foundation

/// Errors surfaced by `EventKitService`. The `description` is user-facing and is
/// what gets shown on the CLI and returned to MCP clients.
public enum EventKitError: Error, CustomStringConvertible, LocalizedError, Sendable {
    case accessDenied(entity: String)
    case notFound(String)
    case invalidArgument(String)
    case saveFailed(String)
    case removeFailed(String)

    public var description: String {
        switch self {
        case .accessDenied(let entity):
            return
                "Access to \(entity) is not granted. Run `\(executableName()) status` once from a terminal and approve the prompt, then re-check System Settings → Privacy & Security."
        case .notFound(let what):
            return "Not found: \(what)"
        case .invalidArgument(let msg):
            return "Invalid argument: \(msg)"
        case .saveFailed(let msg):
            return "Failed to save: \(msg)"
        case .removeFailed(let msg):
            return "Failed to remove: \(msg)"
        }
    }

    public var errorDescription: String? { description }
}
