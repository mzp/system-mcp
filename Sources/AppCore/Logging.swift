import Foundation
import Logging

/// Shared logger for both the CLI and the MCP server.
///
/// Output:
///   - **stderr** always (never stdout — stdout is the MCP protocol / CLI JSON result).
///   - **a file** when a path is configured. This matters for the MCP server: when run
///     by Claude Desktop there is no terminal to watch, so logs are persisted to a file.
///
/// Configuration via environment variables:
///   - `EVENTKITCTL_LOG`      level: trace|debug|info|notice|warning|error|critical (default info)
///   - `EVENTKITCTL_LOG_FILE` explicit log file path (`~` is expanded). Empty disables file logging.
///
/// If `EVENTKITCTL_LOG_FILE` is unset and the process is the MCP server (`serve`),
/// logs default to `~/Library/Logs/eventkitctl.log`.
public let log: Logger = {
    let level = levelFromEnvironment()
    let fileWriter = logFilePath().flatMap(FileLogWriter.init(path:))
    var logger = Logger(label: "eventkitctl") { label in
        var handlers: [any LogHandler] = [StreamLogHandler.standardError(label: label)]
        if let fileWriter {
            handlers.append(FileLogHandler(label: label, writer: fileWriter))
        }
        return MultiplexLogHandler(handlers)
    }
    logger.logLevel = level
    if let path = fileWriter?.path {
        logger.info("logging to file", metadata: ["path": .string(path)])
    }
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

/// Resolves the log file path: explicit env var wins; otherwise default to a file only
/// when running as the MCP server (no terminal to read stderr).
private func logFilePath() -> String? {
    let env = ProcessInfo.processInfo.environment
    if let explicit = env["EVENTKITCTL_LOG_FILE"] {
        return explicit.isEmpty ? nil : (explicit as NSString).expandingTildeInPath
    }
    if CommandLine.arguments.dropFirst().contains("serve") {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Logs/eventkitctl.log").path
    }
    return nil
}

// MARK: - File logging

/// Thread-safe append-only writer shared by a `FileLogHandler`.
final class FileLogWriter: @unchecked Sendable {
    let path: String
    private let handle: FileHandle
    private let lock = NSLock()

    init?(path: String) {
        let fm = FileManager.default
        let dir = (path as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { return nil }
        handle.seekToEndOfFile()
        self.path = path
        self.handle = handle
    }

    func write(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        lock.lock()
        defer { lock.unlock() }
        handle.write(data)
    }
}

/// A swift-log `LogHandler` that appends formatted lines to a file via `FileLogWriter`.
struct FileLogHandler: LogHandler {
    let label: String
    let writer: FileLogWriter
    var logLevel: Logger.Level = .info
    var metadata: Logger.Metadata = [:]

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(event: LogEvent) {
        let merged = self.metadata.merging(event.metadata ?? [:]) { $1 }
        let meta =
            merged.isEmpty
            ? ""
            : " "
                + merged.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        writer.write("\(Self.timestamp()) \(event.level) \(label):\(meta) \(event.message)\n")
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return f
    }()

    private static func timestamp() -> String {
        formatter.string(from: Date())
    }
}
