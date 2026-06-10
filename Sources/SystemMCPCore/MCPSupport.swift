import Foundation
import MCP

// Domain-agnostic helpers shared by both tools' CLI and MCP layers.

// MARK: - JSON Schema builders

public func object(_ properties: [String: Value], required: [String] = []) -> Value {
    .object([
        "type": .string("object"),
        "properties": .object(properties),
        "required": .array(required.map { .string($0) }),
    ])
}

public func string(_ description: String) -> Value {
    .object(["type": .string("string"), "description": .string(description)])
}

public func bool(_ description: String) -> Value {
    .object(["type": .string("boolean"), "description": .string(description)])
}

public func number(_ description: String) -> Value {
    .object(["type": .string("number"), "description": .string(description)])
}

public func stringArray(_ description: String) -> Value {
    .object([
        "type": .string("array"),
        "description": .string(description),
        "items": .object(["type": .string("string")]),
    ])
}

// MARK: - Argument access

extension Optional where Wrapped == [String: Value] {
    public func str(_ key: String) -> String? { self?[key]?.stringValue }
    public func bool(_ key: String) -> Bool? { self?[key]?.boolValue }
    public func double(_ key: String) -> Double? {
        // JSON numbers may decode as int (e.g. 100) or double (e.g. 100.5).
        guard let value = self?[key] else { return nil }
        return value.doubleValue ?? value.intValue.map(Double.init)
    }
    public func strArray(_ key: String) -> [String]? {
        self?[key]?.arrayValue?.compactMap { $0.stringValue }
    }
}

// MARK: - MCP result helpers

public func jsonResult<T: Encodable>(_ value: T) -> CallTool.Result {
    do {
        let data = try DateParsing.jsonEncoder.encode(value)
        return CallTool.Result(
            content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)])
    } catch {
        return errorResult("encoding failed: \(error)")
    }
}

public func errorResult(_ message: String) -> CallTool.Result {
    CallTool.Result(
        content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
}

public func missing(_ field: String) -> CallTool.Result {
    errorResult("missing required argument: \(field)")
}

// MARK: - CLI output

/// Output helpers shared by all CLI subcommands.
public enum Output {
    public static func json<T: Encodable>(_ value: T) {
        do {
            let data = try DateParsing.jsonEncoder.encode(value)
            if let string = String(data: data, encoding: .utf8) {
                print(string)
            }
        } catch {
            FileHandle.standardError.write(Data("encoding error: \(error)\n".utf8))
        }
    }
}

// MARK: - Date parsing

public func parseDateOrThrow(_ string: String, field: String) throws -> Date {
    guard let date = DateParsing.parse(string) else {
        throw EventKitError.invalidArgument("could not parse \(field) date: '\(string)'")
    }
    return date
}
