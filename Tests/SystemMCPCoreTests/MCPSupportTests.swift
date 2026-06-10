import Foundation
import MCP
import Testing

@testable import SystemMCPCore

@Suite struct SchemaBuilderTests {
    @Test func objectBuildsJSONSchema() {
        let schema = object(["title": string("the title")], required: ["title"])
        let obj = schema.objectValue
        #expect(obj?["type"]?.stringValue == "object")
        #expect(obj?["required"]?.arrayValue?.compactMap(\.stringValue) == ["title"])
        let title = obj?["properties"]?.objectValue?["title"]?.objectValue
        #expect(title?["type"]?.stringValue == "string")
        #expect(title?["description"]?.stringValue == "the title")
    }

    @Test func objectDefaultsToNoRequiredFields() {
        let schema = object([:])
        #expect(schema.objectValue?["required"]?.arrayValue?.isEmpty == true)
    }

    @Test func boolBuildsBooleanSchema() {
        let schema = bool("a flag").objectValue
        #expect(schema?["type"]?.stringValue == "boolean")
        #expect(schema?["description"]?.stringValue == "a flag")
    }

    @Test func stringArrayBuildsArrayOfStringsSchema() {
        let schema = stringArray("ids").objectValue
        #expect(schema?["type"]?.stringValue == "array")
        #expect(schema?["items"]?.objectValue?["type"]?.stringValue == "string")
    }

    @Test func numberBuildsNumberSchema() {
        let schema = number("radius in meters").objectValue
        #expect(schema?["type"]?.stringValue == "number")
        #expect(schema?["description"]?.stringValue == "radius in meters")
    }
}

@Suite struct ArgumentAccessTests {
    let args: [String: Value]? = [
        "title": .string("buy milk"),
        "flag": .bool(true),
        "ids": .array([.string("a"), .string("b")]),
        "mixed": .array([.string("a"), .int(1)]),
        "number": .int(42),
        "fraction": .double(100.5),
    ]

    @Test func readsTypedValues() {
        #expect(args.str("title") == "buy milk")
        #expect(args.bool("flag") == true)
        #expect(args.strArray("ids") == ["a", "b"])
    }

    @Test func doubleReadsBothIntAndDouble() {
        #expect(args.double("fraction") == 100.5)
        #expect(args.double("number") == 42.0)  // JSON ints coerce to Double
        #expect(args.double("title") == nil)
        #expect(args.double("nope") == nil)
    }

    @Test func returnsNilForMissingOrMistypedKeys() {
        #expect(args.str("nope") == nil)
        #expect(args.str("flag") == nil)
        #expect(args.bool("title") == nil)
        #expect(args.strArray("title") == nil)
    }

    @Test func strArrayDropsNonStringElements() {
        #expect(args.strArray("mixed") == ["a"])
    }

    @Test func nilArgumentsReturnNil() {
        let none: [String: Value]? = nil
        #expect(none.str("title") == nil)
        #expect(none.bool("flag") == nil)
        #expect(none.strArray("ids") == nil)
    }
}

@Suite struct ResultHelperTests {
    private func text(of result: CallTool.Result) -> String? {
        guard case .text(let text, _, _) = result.content.first else { return nil }
        return text
    }

    @Test func jsonResultEncodesValueAsJSONText() throws {
        let result = jsonResult(StatusResponse(entity: "reminders", status: "fullAccess"))
        #expect(result.isError != true)
        let json = try #require(text(of: result))
        let decoded = try DateParsing.jsonDecoder.decode(
            StatusResponse.self, from: Data(json.utf8))
        #expect(decoded.entity == "reminders")
        #expect(decoded.status == "fullAccess")
    }

    @Test func errorResultIsMarkedAsError() {
        let result = errorResult("boom")
        #expect(result.isError == true)
        #expect(text(of: result) == "boom")
    }

    @Test func missingNamesTheField() {
        let result = missing("title")
        #expect(result.isError == true)
        #expect(text(of: result) == "missing required argument: title")
    }
}

@Suite struct ParseDateOrThrowTests {
    @Test func returnsParsedDate() throws {
        let date = try parseDateOrThrow("2026-06-10", field: "start")
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        #expect(c.year == 2026)
        #expect(c.month == 6)
        #expect(c.day == 10)
    }

    @Test func throwsInvalidArgumentNamingTheField() {
        #expect {
            try parseDateOrThrow("garbage", field: "start")
        } throws: { error in
            guard case EventKitError.invalidArgument(let message) = error else { return false }
            return message.contains("start") && message.contains("garbage")
        }
    }
}
