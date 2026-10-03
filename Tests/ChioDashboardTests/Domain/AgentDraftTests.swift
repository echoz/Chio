@testable import ChioDashboard
import Testing

struct AgentDraftTests {
    @Test("Required fields follow visible form order and invalid drafts cannot create agents")
    func requiredFields() {
        var draft = AgentDraft()
        #expect(draft.issues.map(\.field) == [.name])
        #expect(draft.makeAgent(id: "invalid") == nil)
        draft.role = .test
        #expect(draft.issues.map(\.field) == [.name, .suite])
        draft.name = "Verifier"
        #expect(draft.issues.map(\.field) == [.suite])
        #expect(draft.makeAgent(id: "invalid") == nil)
    }

    @Test(arguments: ["", " ", "\n\t "])
    func whitespaceNameIsRequired(_ name: String) {
        var draft = AgentDraft()
        draft.name = name
        #expect(draft.issues.map(\.field) == [.name])
        #expect(draft.makeAgent(id: "invalid") == nil)
    }

    @Test("Limits count trimmed user-perceived characters")
    func characterBoundaries() {
        var draft = AgentDraft()
        draft.name = " \n" + String(repeating: "👩🏽‍💻", count: 32) + "\t "
        #expect(draft.issues.isEmpty)
        #expect(draft.makeAgent(id: "unicode")?.name.count == 32)
        draft.name += "a"
        #expect(draft.issues.map(\.field) == [.name])
        draft.name = "Verifier"
        draft.role = .test
        draft.suite = " " + String(repeating: "é", count: 40) + "\n"
        #expect(draft.issues.isEmpty)
        draft.suite += "x"
        #expect(draft.issues.map(\.field) == [.suite])
        #expect(draft.makeAgent(id: "invalid") == nil)
    }

    @Test("Hidden suite values are retained and only Test validates them")
    func conditionalSuiteRetention() {
        var draft = AgentDraft()
        draft.name = "Verifier"
        draft.role = .test
        draft.suite = "  Integration tests  "
        draft.role = .review
        #expect(draft.suite == "  Integration tests  ")
        #expect(draft.issues.isEmpty)
        #expect(draft.makeAgent(id: "review")?.summary == "Read · inspect · suggest")
        draft.role = .test
        #expect(draft.makeAgent(id: "test")?.summary == "Test suite · Integration tests")
        draft.suite = " \n\t "
        #expect(draft.issues.map(\.field) == [.suite])
        draft.role = .docs
        #expect(draft.issues.isEmpty)
        #expect(draft.suite == " \n\t ")
    }

    @Test("Creation preserves injected identity, trims boundaries, and chooses the requested phase")
    func creationValues() throws {
        var draft = AgentDraft()
        draft.name = "  Release  agent\n"
        let running = try #require(draft.makeAgent(id: "stable-id"))
        #expect(running.id == "stable-id")
        #expect(running.name == "Release  agent")
        #expect(running.summary == "Compile · resolve · package")
        #expect(running.phase == .running(progress: 0))
        draft.startImmediately = false
        let idle = try #require(draft.makeAgent(id: "idle-id"))
        #expect(idle.id == "idle-id")
        #expect(idle.phase == .idle)
        #expect(draft.name == "  Release  agent\n")
    }
}
