@testable import ChioDashboard
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct TextEntryExampleTests {
    @Test("Native masked editing, Tab, Return, paste, validation and cancellation compose")
    func completeForm() async throws {
        try await withTextEntryExample { session, _, recorder in
            _ = try await recorder.wait(description: "initial password focus") { $0.passwordFocused }
            session.send(.key(.character("s"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "empty submission focuses first invalid field") {
                $0.passwordFocused && $0.entryContains("Error: Use at least 8 characters.")
                    && $0.entryContains("Error: Enter some notes.")
            }
            session.sendInput(Array("Fixture8x".utf8))
            let typed = try await recorder.wait(description: "native password entry remains masked") {
                $0.maskedCharacterCount == 9 && !$0.entryContains("Error: Use at least 8 characters.")
            }
            #expect(typed.concealsSyntheticPassword)
            session.send(.key(.arrowLeft))
            session.send(.key(.backspace))
            _ = try await recorder.wait(description: "native password caret deletion") { $0.maskedCharacterCount == 8 }
            session.send(.key(.character("s"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "valid password focuses invalid notes") {
                $0.notesFocused && $0.entryContains("Error: Enter some notes.")
            }
            session.sendInput(Array("First note".utf8))
            session.send(.key(.return))
            session.send(.paste(PasteEvent(content: "Second note\nThird note")))
            let entered = try await recorder.wait(description: "native editor retains Return and multiline paste") {
                $0.notesValue("First note\nSecond note\nThird note")
            }
            #expect(!entered.entryContains("Accepted"))
            session.send(.key(.tab, modifiers: .shift))
            _ = try await recorder.wait(description: "native Shift-Tab returns to password") { $0.passwordFocused }
            session.send(.key(.tab))
            _ = try await recorder.wait(description: "native Tab returns to notes") { $0.notesFocused }
            session.send(.key(.character("s"), modifiers: .ctrl))
            let accepted = try await recorder.wait(description: "accepted draft clears only password") {
                $0.entryContains("Accepted · password cleared") && $0.maskedCharacterCount == 0
                    && $0.notesValue("First note\nSecond note\nThird note")
            }
            #expect(accepted.concealsSyntheticPassword)
            #expect(!accepted.entryContains("Error:"))
            session.send(.key(.character("!")))
            _ = try await recorder.wait(description: "editing notes clears stale acceptance") {
                !$0.entryContains("Accepted") && $0.notesValue("First note\nSecond note\nThird note!")
            }
            session.send(.key(.character("x"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "Cancel clears both fields and restores native password focus") {
                $0.passwordFocused && $0.entryContains("Cancelled") && $0.maskedCharacterCount == 0
                    && $0.notesValue("") && !$0.entryContains("Error:")
            }
        }
    }

    @Test("Theme, compact resize and disabled inputs preserve drafts and leave cancel and unlock usable")
    func compactDisabledInteraction() async throws {
        try await withTextEntryExample { session, surface, recorder in
            _ = try await recorder.wait(description: "password ready") { $0.passwordFocused }
            session.sendInput(Array("Fixture8x".utf8))
            _ = try await recorder.wait(description: "masked password ready") { $0.maskedCharacterCount == 9 }
            session.send(.key(.tab))
            _ = try await recorder.wait(description: "notes ready") { $0.notesFocused }
            session.send(.paste(PasteEvent(content: "Compact note\nSecond line")))
            let before = try await recorder.wait(description: "draft entered") {
                $0.notesFocused && $0.notesValue("Compact note\nSecond line")
            }
            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(after: before.sequence, description: "theme retains native editor focus") {
                $0.raster.cells != before.raster.cells && $0.notesFocused
            }
            #expect(themed.focusedIdentity == before.focusedIdentity)
            surface.updateSurfaceSize(.init(width: 36, height: 18))
            session.requestSurfaceRefresh()
            let compact = try await recorder.wait(after: themed.sequence, description: "compact editor retains draft and focus") {
                $0.raster.size == CellSize(width: 36, height: 18) && $0.notesFocused
            }
            #expect(compact.notesValue("Compact note\nSecond line"))
            #expect(compact.concealsSyntheticPassword)
            #expect(compact.entryContains("Save") && compact.entryContains("Cancel"))
            #expect(compact.entryContains("^S save") && compact.entryContains("^Q quit"))
            session.send(.key(.character("d"), modifiers: .ctrl))
            let locked = try await recorder.wait(description: "lock preserves draft and exposes unlock") {
                $0.entryContains("Inputs locked") && $0.entryContains("^D unlock")
            }
            session.sendInput(Array("blocked".utf8))
            session.send(.key(.character("s"), modifiers: .ctrl))
            session.requestSurfaceRefresh()
            let unchanged = try await recorder.wait(after: locked.sequence, description: "locked editor ignores edits and Save") {
                $0.entryContains("Inputs locked")
            }
            #expect(unchanged.notesValue("Compact note\nSecond line"))
            #expect(unchanged.maskedCharacterCount == 9)
            #expect(!unchanged.entryContains("Accepted"))
            session.send(.key(.character("x"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "Cancel remains available while locked") {
                $0.notesValue("") && $0.maskedCharacterCount == 0
            }
            session.send(.key(.character("d"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "unlock restores password focus with cancel feedback") {
                $0.passwordFocused && $0.entryContains("Cancelled") && $0.entryContains("^D lock")
            }
        }
    }

    @Test("Editing a password after acceptance clears stale feedback while theme changes preserve it")
    func acceptanceFeedback() async throws {
        try await withTextEntryExample(password: "Fixture8x", notes: "Local note") { session, _, recorder in
            _ = try await recorder.wait(description: "populated password ready") { $0.passwordFocused }
            session.send(.key(.character("s"), modifiers: .ctrl))
            let accepted = try await recorder.wait(description: "accepted password cleared") {
                $0.entryContains("Accepted · password cleared") && $0.maskedCharacterCount == 0
            }
            session.send(.key(.character("t"), modifiers: .ctrl))
            _ = try await recorder.wait(after: accepted.sequence, description: "theme preserves acceptance") {
                $0.raster.cells != accepted.raster.cells && $0.entryContains("Accepted · password cleared")
            }
            session.send(.key(.character("a")))
            _ = try await recorder.wait(description: "new password clears old acceptance") {
                $0.maskedCharacterCount == 1 && !$0.entryContains("Accepted")
            }
        }
    }
}

private struct TextEntryTestApp {
    let password: String
    let notes: String

    nonisolated init() { password = ""; notes = "" }
    nonisolated init(password: String, notes: String) { self.password = password; self.notes = notes }
}

extension TextEntryTestApp: App {
    var body: some Scene {
        WindowGroup(id: "text-entry-example-tests") {
            TextEntryExampleView(initialPassword: password, initialNotes: notes)
        }.exitOnKeys([])
    }
}

@MainActor
private func withTextEntryExample(
    password: String = "", notes: String = "",
    perform: @MainActor (HostedSceneSession, HostedRasterSurface, HostedFrameRecorder) async throws -> Void
) async throws {
    let recorder = HostedFrameRecorder()
    let surface = HostedRasterSurface(surfaceSize: .init(width: 76, height: 30), appearance: .fallback,
                                      onFrame: { frame in
                                          let concealsSyntheticPassword = frame.concealsSyntheticPassword
                                          let secureMetadataConcealsValue = frame.semantics.accessibilityNodes
                                              .filter { $0.role == .secureField }
                                              .allSatisfy { $0.textInput == nil && $0.control?.value == nil }
                                          #expect(concealsSyntheticPassword)
                                          #expect(secureMetadataConcealsValue)
                                          recorder.receive(frame)
                                      })
    let session = try HostedSceneSession(for: TextEntryTestApp(password: password, notes: notes),
                                        sceneID: "text-entry-example-tests", surface: surface)
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
    func entryContains(_ text: String) -> Bool { raster.lines.contains { $0.contains(text) } }
    var maskedCharacterCount: Int { raster.cells.flatMap { $0 }.filter { $0.character == "•" }.count }
    var passwordFocused: Bool {
        semantics.accessibilityNodes.contains { $0.identity == focusedIdentity && $0.role == .secureField }
    }
    var notesFocused: Bool {
        semantics.accessibilityNodes.contains { $0.identity == focusedIdentity && $0.role == .textEditor }
    }
    func notesValue(_ value: String) -> Bool {
        semantics.accessibilityNodes.contains { $0.role == .textEditor && $0.control?.value == .text(value) }
    }
    var concealsSyntheticPassword: Bool {
        !raster.lines.joined(separator: "\n").contains("Fixtur")
            && !String(reflecting: semantics).contains("Fixtur")
    }
}
