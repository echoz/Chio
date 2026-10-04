@testable import ChioDashboard
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct ChoiceExampleTests {
    @Test("Searchable single choice, hidden checks, validation, save and cancellation compose")
    func completeForm() async throws {
        try await withChoiceExample { session, _, recorder in
            _ = try await recorder.wait(description: "language results ready") {
                $0.choiceContains("1 / 2") && $0.choiceResultsFocused
            }
            session.sendInput(Array("/rust\r\r".utf8))
            _ = try await recorder.wait(description: "Rust advances to capabilities and search") {
                $0.choiceContains("2 / 2") && $0.choiceEditorFocused
            }
            session.send(.key(.character("s"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "empty selection rejected") {
                $0.choiceContains("Error: Choose at least 1")
            }
            try await checkChoice("build", label: "Build", session: session, recorder: recorder)
            session.send(.key(.escape))
            _ = try await recorder.wait(description: "all choices restored") { $0.choiceContains("6 of 6 items") }
            session.send(.key(.character("/")))
            _ = try await recorder.wait(description: "native search ready for second choice") { $0.choiceEditorFocused }
            try await checkChoice("test", label: "Test", session: session, recorder: recorder)
            let selected = try await recorder.wait(description: "hidden Build retained with Test") {
                $0.choiceContains("2 selected") && $0.choiceContains("1 hidden")
            }
            #expect(!selected.choiceContains("Error:"))
            session.send(.key(.character("s"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "valid choices captured on Save") {
                $0.choiceContains("Saved: Rust · Build, Test")
            }
            session.send(.key(.space))
            _ = try await recorder.wait(description: "editing after Save clears success feedback") {
                $0.choiceContains("1 selected") && $0.choiceContains("unsaved choices") && !$0.choiceContains("Saved:")
            }
            session.send(.key(.character("b"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "Back retains language query and selection") {
                $0.choiceContains("1 / 2") && $0.choiceQuery("rust") && $0.choiceContains("1 of 4 items")
                    && $0.choiceResultsFocused
            }
            session.sendInput(Array("\r\r".utf8))
            let returned = try await recorder.wait(description: "repeated old language activation cannot save capabilities") {
                $0.choiceContains("2 / 2") && $0.choiceEditorFocused
            }
            #expect(returned.choiceContains("1 selected"))
            #expect(returned.choiceContains("unsaved choices"))
            #expect(!returned.choiceContains("Saved:"))
            session.send(.key(.character("b"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "Back remains usable after repeated activation") {
                $0.choiceContains("1 / 2") && $0.choiceResultsFocused
            }
            session.send(.key(.character("x"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "Cancel restores original language and clears query") {
                $0.choiceContains("Cancelled") && $0.choiceQuery("") && $0.choiceContains("4 of 4 items")
            }
            session.send(.key(.character("s"), modifiers: .ctrl))
            let cancelled = try await recorder.wait(description: "Cancel also restores original empty capabilities") {
                $0.choiceContains("2 / 2") && $0.choiceContains("0 selected")
            }
            #expect(!cancelled.choiceContains("Saved:"))
        }
    }

    @Test("Over-limit choices remain editable and unavailable choices cannot be saved")
    func validationBoundaries() async throws {
        try await withChoiceExample(
            draft: ChoiceDraft(capabilities: [.build, .test, .lint, .format]), step: .capabilities
        ) { session, _, recorder in
            _ = try await recorder.wait(description: "over-limit draft ready") {
                $0.choiceEditorFocused && $0.choiceContains("4 selected")
            }
            session.send(.key(.character("s"), modifiers: .ctrl))
            let invalid = try await recorder.wait(description: "maximum error without truncation") {
                $0.choiceContains("Error: Choose at most 3")
            }
            #expect(invalid.choiceContains("4 selected"))
            #expect(!invalid.choiceContains("Saved:"))
            session.sendInput(Array("format".utf8))
            _ = try await recorder.wait(description: "Format filter ready") { $0.choiceQuery("format") }
            session.send(.key(.return))
            _ = try await recorder.wait(description: "Format row ready to uncheck") { $0.choiceRowFocused("Format") }
            session.send(.key(.space))
            _ = try await recorder.wait(description: "user removes fourth choice") { $0.choiceContains("3 selected") }
            session.send(.key(.character("s"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "corrected choices save") {
                $0.choiceContains("Saved: Swift · Build, Test, Lint")
            }
            session.send(.key(.space))
            _ = try await recorder.wait(description: "fourth choice can be checked again") { $0.choiceContains("4 selected") }
            session.send(.key(.character("s"), modifiers: .ctrl))
            let rejectedAfterSave = try await recorder.wait(description: "failed save replaces stale success feedback") {
                $0.choiceContains("Not saved") && $0.choiceContains("Error: Choose at most 3")
            }
            #expect(!rejectedAfterSave.choiceContains("Saved:"))
        }
        try await withChoiceExample(draft: ChoiceDraft(capabilities: [.deploy]), step: .capabilities) { session, _, recorder in
            _ = try await recorder.wait(description: "unavailable draft ready") { $0.choiceEditorFocused }
            session.send(.key(.character("s"), modifiers: .ctrl))
            let invalid = try await recorder.wait(description: "current availability checked on Save") {
                $0.choiceContains("Error: Unavailable: Deploy.")
            }
            #expect(!invalid.choiceContains("Saved:"))
            session.send(.key(.character("r"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "explicit Reset removes unavailable choice") {
                $0.choiceContains("0 selected") && $0.choiceContains("Reset") && !$0.choiceContains("Error:")
            }
        }
    }

    @Test("Focused multi-choice editing survives theme and compact resize with visible actions")
    func compactInteraction() async throws {
        try await withChoiceExample(draft: ChoiceDraft(capabilities: [.build]), step: .capabilities) { session, surface, recorder in
            _ = try await recorder.wait(description: "capability editor ready") { $0.choiceEditorFocused }
            try await checkChoice("test", label: "Test", session: session, recorder: recorder)
            let before = try await recorder.wait(description: "two checked choices") {
                $0.choiceContains("2 selected") && $0.choiceRowFocused("Test")
            }
            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(after: before.sequence, description: "theme changed with native row focus") {
                $0.raster.cells != before.raster.cells && $0.choiceRowFocused("Test")
            }
            #expect(themed.focusedIdentity == before.focusedIdentity)
            surface.updateSurfaceSize(.init(width: 36, height: 18))
            session.requestSurfaceRefresh()
            let compact = try await recorder.wait(after: themed.sequence, description: "compact form still navigable") {
                $0.raster.size == CellSize(width: 36, height: 18) && $0.choiceRowFocused("Test")
            }
            #expect(compact.focusedIdentity == before.focusedIdentity)
            #expect(compact.choiceContains("2 selected"))
            #expect(compact.choiceContains("1 hidden"))
            #expect(compact.choiceContains("Save") && compact.choiceContains("Cancel"))
            #expect(compact.choiceContains("^S save") && compact.choiceContains("^Q quit"))
            session.send(.key(.space))
            _ = try await recorder.wait(description: "compact native toggle still works") { $0.choiceContains("1 selected") }
            session.send(.key(.character("s"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "compact save retains hidden Build") {
                $0.choiceContains("Saved: Swift · Build")
            }
        }
    }
}

@MainActor
private func checkChoice(_ query: String, label: String, session: HostedSceneSession, recorder: HostedFrameRecorder) async throws {
    session.sendInput(Array(query.utf8))
    _ = try await recorder.wait(description: "query \(query) is current") { $0.choiceQuery(query) }
    session.send(.key(.return))
    let row = try await recorder.wait(description: "native \(label) row focused") { $0.choiceRowFocused(label) }
    session.send(.key(.space))
    _ = try await recorder.wait(after: row.sequence, description: "\(label) checked") {
        $0.raster.lines.contains { $0.contains(label) && $0.contains("[x]") }
    }
}

private struct ChoiceTestApp {
    let draft: ChoiceDraft
    let step: ChoiceExampleView.Step

    nonisolated init() { draft = ChoiceDraft(); step = .language }
    nonisolated init(draft: ChoiceDraft, step: ChoiceExampleView.Step) {
        self.draft = draft
        self.step = step
    }
}

extension ChoiceTestApp: App {
    var body: some Scene {
        WindowGroup(id: "choice-example-tests") {
            ChoiceExampleView(initialDraft: draft, initialStep: step)
        }.exitOnKeys([])
    }
}

@MainActor
private func withChoiceExample(
    draft: ChoiceDraft = ChoiceDraft(), step: ChoiceExampleView.Step = .language,
    perform: @MainActor (HostedSceneSession, HostedRasterSurface, HostedFrameRecorder) async throws -> Void
) async throws {
    let recorder = HostedFrameRecorder()
    let surface = HostedRasterSurface(surfaceSize: .init(width: 76, height: 30), appearance: .fallback,
                                      onFrame: { recorder.receive($0) })
    let session = try HostedSceneSession(for: ChoiceTestApp(draft: draft, step: step),
                                        sceneID: "choice-example-tests", surface: surface)
    let run = Task { try await session.start() }
    defer { session.stop() }
    do {
        try await perform(session, surface, recorder)
        session.stop()
        #expect(try await run.value == .inputEnded)
    } catch {
        session.stop()
        _ = await run.result
        throw error
    }
}

private extension SemanticHostFrame {
    func choiceContains(_ text: String) -> Bool { raster.lines.contains { $0.contains(text) } }
    func choiceQuery(_ query: String) -> Bool {
        semantics.accessibilityNodes.contains { $0.role == .textField && $0.control?.value == .text(query) }
    }
    var choiceEditorFocused: Bool {
        semantics.accessibilityNodes.contains { $0.identity == focusedIdentity && $0.role == .textField }
    }
    var choiceResultsFocused: Bool {
        !choiceEditorFocused && semantics.focusRegions.contains { $0.identity == focusedIdentity }
    }
    func choiceRowFocused(_ label: String) -> Bool {
        !choiceEditorFocused && raster.lines.contains { $0.contains(label) && $0.contains("▌") }
    }
}
