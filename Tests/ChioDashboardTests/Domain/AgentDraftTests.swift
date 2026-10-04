@testable import ChioDashboard
import Foundation
import Testing

struct AgentDraftTests {
    @Test("Replacements preserve unspecified values and leave the original draft unchanged")
    func replacements() {
        let original = AgentDraft(name: "Verifier", role: .test, suite: "Integration", startImmediately: true)
        let changed = original.replacing(name: "", role: .review, suite: "", startImmediately: false)
        #expect(changed == AgentDraft(name: "", role: .review, suite: "", startImmediately: false))
        #expect(original == AgentDraft(name: "Verifier", role: .test, suite: "Integration", startImmediately: true))
        #expect(original.replacing() == original)
        #expect(original.replacing(name: "New") == AgentDraft(name: "New", role: .test, suite: "Integration"))
        #expect(original.replacing(role: .review) == AgentDraft(name: "Verifier", role: .review, suite: "Integration"))
        #expect(original.replacing(suite: "Unit") == AgentDraft(name: "Verifier", role: .test, suite: "Unit"))
        #expect(original.replacing(startImmediately: false) == AgentDraft(name: "Verifier", role: .test, suite: "Integration", startImmediately: false))
        #expect(changed.makeAgent(id: "invalid") == nil)
    }

    @Test("Draft codecs preserve editable values without bypassing creation validation")
    func draftCodecs() throws {
        let original = AgentDraft(name: "  Verifier  ", role: .test, suite: "", startImmediately: false)
        let decoded = try JSONDecoder().decode(AgentDraft.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(Set([original, decoded]).count == 1)
        #expect(decoded.issues.map(\.field) == [.suite])
        #expect(decoded.makeAgent(id: "invalid") == nil)
        #expect(decoded.replacing(suite: " Unit ").makeAgent(id: "valid")?.summary == "Test suite · Unit")
        for field in [AgentDraft.Field.name, .suite] {
            let data = try JSONEncoder().encode(field)
            #expect(try JSONDecoder().decode(AgentDraft.Field.self, from: data) == field)
        }
    }

    @Test("Required fields follow visible form order and invalid drafts cannot create agents")
    func requiredFields() {
        var draft = AgentDraft()
        #expect(draft.issues.map(\.field) == [.name])
        #expect(draft.makeAgent(id: "invalid") == nil)
        draft = draft.replacing(role: .test)
        #expect(draft.issues.map(\.field) == [.name, .suite])
        draft = draft.replacing(name: "Verifier")
        #expect(draft.issues.map(\.field) == [.suite])
        #expect(draft.makeAgent(id: "invalid") == nil)
    }

    @Test(arguments: ["", " ", "\n\t "])
    func whitespaceNameIsRequired(_ name: String) {
        var draft = AgentDraft()
        draft = draft.replacing(name: name)
        #expect(draft.issues.map(\.field) == [.name])
        #expect(draft.makeAgent(id: "invalid") == nil)
    }

    @Test("Limits count trimmed user-perceived characters")
    func characterBoundaries() {
        var draft = AgentDraft()
        draft = draft.replacing(name: " \n" + String(repeating: "👩🏽‍💻", count: 32) + "\t ")
        #expect(draft.issues.isEmpty)
        #expect(draft.makeAgent(id: "unicode")?.name.count == 32)
        draft = draft.replacing(name: draft.name + "a")
        #expect(draft.issues.map(\.field) == [.name])
        draft = draft.replacing(name: "Verifier")
        draft = draft.replacing(role: .test)
        draft = draft.replacing(suite: " " + String(repeating: "é", count: 40) + "\n")
        #expect(draft.issues.isEmpty)
        draft = draft.replacing(suite: draft.suite + "x")
        #expect(draft.issues.map(\.field) == [.suite])
        #expect(draft.makeAgent(id: "invalid") == nil)
    }

    @Test("Hidden suite values are retained and only Test validates them")
    func conditionalSuiteRetention() {
        var draft = AgentDraft()
        draft = draft.replacing(name: "Verifier")
        draft = draft.replacing(role: .test)
        draft = draft.replacing(suite: "  Integration tests  ")
        draft = draft.replacing(role: .review)
        #expect(draft.suite == "  Integration tests  ")
        #expect(draft.issues.isEmpty)
        #expect(draft.makeAgent(id: "review")?.summary == "Read · inspect · suggest")
        draft = draft.replacing(role: .test)
        #expect(draft.makeAgent(id: "test")?.summary == "Test suite · Integration tests")
        draft = draft.replacing(suite: " \n\t ")
        #expect(draft.issues.map(\.field) == [.suite])
        draft = draft.replacing(role: .docs)
        #expect(draft.issues.isEmpty)
        #expect(draft.suite == " \n\t ")
    }

    @Test("Creation preserves injected identity, trims boundaries, and chooses the requested phase")
    func creationValues() throws {
        var draft = AgentDraft()
        draft = draft.replacing(name: "  Release  agent\n")
        let running = try #require(draft.makeAgent(id: "stable-id"))
        #expect(running.id == "stable-id")
        #expect(running.name == "Release  agent")
        #expect(running.summary == "Compile · resolve · package")
        #expect(running.phase == .running(progress: .zero))
        draft = draft.replacing(startImmediately: false)
        let idle = try #require(draft.makeAgent(id: "idle-id"))
        #expect(idle.id == "idle-id")
        #expect(idle.phase == .idle)
        #expect(draft.name == "  Release  agent\n")
    }
}
