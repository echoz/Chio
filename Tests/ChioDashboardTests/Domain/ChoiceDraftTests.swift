@testable import ChioDashboard
import Foundation
import Testing

struct ChoiceDraftTests {
    private let available = Set(ChoiceDraft.Capability.allCases.filter { $0 != .deploy })

    @Test("Choice replacement preserves other fields and the original")
    func replacements() {
        let original = ChoiceDraft(language: .rust, capabilities: [.test, .docs])
        #expect(original.replacing() == original)
        #expect(original.replacing(language: .go) == ChoiceDraft(language: .go, capabilities: [.test, .docs]))
        #expect(original.replacing(capabilities: []) == ChoiceDraft(language: .rust))
        #expect(original == ChoiceDraft(language: .rust, capabilities: [.test, .docs]))
    }

    @Test("Save requires one through three capabilities without truncating the draft")
    func limits() {
        let empty = ChoiceDraft()
        #expect(empty.validationMessage(availableCapabilities: available) == "Choose at least 1 capability.")
        let selections: [Set<ChoiceDraft.Capability>] = [[.build], [.build, .test], [.build, .test, .lint]]
        for selected in selections {
            #expect(empty.replacing(capabilities: selected).validationMessage(availableCapabilities: available) == nil)
        }
        let tooMany = empty.replacing(capabilities: [.build, .test, .lint, .format])
        #expect(tooMany.validationMessage(availableCapabilities: available) == "Choose at most 3 capabilities.")
        #expect(tooMany.capabilities == [.build, .test, .lint, .format])
    }

    @Test("Availability is checked against current options at save time")
    func currentAvailability() {
        let draft = ChoiceDraft(capabilities: [.build, .deploy])
        #expect(draft.validationMessage(availableCapabilities: available) == "Unavailable: Deploy.")
        #expect(draft.validationMessage(availableCapabilities: [.build, .deploy]) == nil)
        #expect(draft.validationMessage(availableCapabilities: [.deploy]) == "Unavailable: Build.")
        #expect(draft.capabilities == [.build, .deploy])
    }

    @Test("Draft codecs retain incomplete and unavailable choices for runtime validation")
    func codecs() throws {
        for draft in [ChoiceDraft(), ChoiceDraft(language: .rust, capabilities: [.build, .test]),
                      ChoiceDraft(language: .python, capabilities: [.deploy]),
                      ChoiceDraft(language: .go, capabilities: [.build, .test, .docs, .format])] {
            let decoded = try JSONDecoder().decode(ChoiceDraft.self, from: JSONEncoder().encode(draft))
            #expect(decoded == draft)
            #expect(decoded.validationMessage(availableCapabilities: available) == draft.validationMessage(availableCapabilities: available))
            #expect(Set([draft, decoded]).count == 1)
        }
        for language in ChoiceDraft.Language.allCases {
            #expect(language.id == language)
            #expect(try JSONDecoder().decode(ChoiceDraft.Language.self, from: JSONEncoder().encode(language)) == language)
        }
        for capability in ChoiceDraft.Capability.allCases {
            #expect(capability.id == capability)
            #expect(try JSONDecoder().decode(ChoiceDraft.Capability.self, from: JSONEncoder().encode(capability)) == capability)
        }
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(ChoiceDraft.Language.self, from: Data("\"unknown\"".utf8))
        }
    }

    @Test("Saved display ordering follows fixture order rather than set iteration")
    func displayOrder() {
        #expect(ChoiceDraft(language: .python, capabilities: [.docs, .build, .test]).summary == "Python · Build, Test, Docs")
        #expect(ChoiceDraft().summary == "Swift · none selected")
    }
}
