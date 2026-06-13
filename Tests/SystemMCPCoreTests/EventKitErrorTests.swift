import Foundation
import Testing

@testable import SystemMCPCore

@Suite struct EventKitErrorTests {
    @Test func accessDeniedMentionsEntityAndStatusCommand() {
        let description = EventKitError.accessDenied(entity: "reminders").description
        #expect(description.contains("reminders"))
        #expect(description.contains("status"))
        #expect(description.contains(executableName()))
    }

    @Test func descriptionsIncludeTheMessage() {
        #expect(EventKitError.notFound("list 'X'").description == "Not found: list 'X'")
        #expect(EventKitError.invalidArgument("bad").description == "Invalid argument: bad")
        #expect(EventKitError.saveFailed("io").description == "Failed to save: io")
        #expect(EventKitError.removeFailed("io").description == "Failed to remove: io")
    }

    @Test func ambiguousListsTheCandidateIds() {
        let description = EventKitError.ambiguous(
            label: "reminder list", name: "家事", candidateIds: ["AB1B", "6F41"]
        ).description
        #expect(description.contains("Ambiguous reminder list '家事'"))
        #expect(description.contains("AB1B"))
        #expect(description.contains("6F41"))
    }

    @Test func errorDescriptionMatchesDescription() {
        let error = EventKitError.notFound("x")
        #expect(error.errorDescription == error.description)
        // LocalizedError plumbing: NSError-bridged message matches too.
        #expect(error.localizedDescription == error.description)
    }
}
