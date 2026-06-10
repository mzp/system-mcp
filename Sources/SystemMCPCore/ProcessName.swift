import Foundation

/// The basename of the running executable (e.g. `apple-reminder`).
///
/// Both tools share `SystemMCPCore`, so logging labels, the default log file name, and
/// user-facing error hints are derived from this at runtime instead of being hard-coded.
public func executableName() -> String {
    let arg0 = CommandLine.arguments.first ?? "SystemMCP"
    let name = (arg0 as NSString).lastPathComponent
    return name.isEmpty ? "SystemMCP" : name
}
