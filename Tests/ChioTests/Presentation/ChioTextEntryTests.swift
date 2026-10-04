import Chio
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct ChioTextEntryTests {
    @Test("Secure editing stays masked through submission, focus, theme and disabled state")
    func secureEditing() async throws {
        try await withTextEntry { session, _, recorder in
            _ = try await recorder.wait(description: "secure field initially focused") { $0.textEntryFocus(.secureField) }
            session.sendInput(Array("Synthetic-482!".utf8))
            let entered = try await recorder.wait(description: "native secure binding edited") { $0.textEntryContains("Length=14") }
            #expect(entered.textEntryFocus(.secureField))
            session.send(.key(.return))
            _ = try await recorder.wait(description: "secure Return submits") { $0.textEntryContains("Submits=1") }
            session.send(.key(.backspace))
            _ = try await recorder.wait(description: "secure backspace edits binding") { $0.textEntryContains("Length=13") }
            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(description: "secure focus retained in light theme") {
                $0.textEntryContains("Light=true") && $0.textEntryFocus(.secureField)
            }
            #expect(themed.focusedIdentity == entered.focusedIdentity)
            session.send(.key(.character("d"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "disabled inputs leave native focus ring") {
                $0.semantics.accessibilityNodes.filter { $0.role == .secureField || $0.role == .textEditor }.allSatisfy { !$0.isEnabled }
                    && $0.textEntryFocus(.button)
            }
            session.sendInput(Array("NoEdit".utf8))
            session.send(.key(.character("t"), modifiers: .ctrl))
            let disabled = try await recorder.wait(after: themed.sequence, description: "disabled input unchanged after another rendered action") {
                $0.textEntryContains("Light=false")
            }
            #expect(disabled.textEntryContains("Length=13"))
            #expect(disabled.textEntryContains("Submits=1"))
            session.send(.key(.character("d"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "reenabled secure editing receives focus") { $0.textEntryFocus(.secureField) }
            session.send(.key(.character("Z")))
            _ = try await recorder.wait(description: "reenabled native input changes binding") { $0.textEntryContains("Length=14") }
            session.send(.paste(.init(content: "A\nB")))
            _ = try await recorder.wait(description: "secure paste uses native single-line filtering") { $0.textEntryContains("Length=16") }
        }
    }

    @Test("Native multiline paste, wrapped caret movement, selection and scrolling survive style and resize")
    func multilineEditing() async throws {
        try await withTextEntry { session, surface, recorder in
            _ = try await recorder.wait(description: "native secure focus ready") { $0.textEntryFocus(.secureField) }
            session.send(.key(.tab))
            _ = try await recorder.wait(description: "Tab reaches one native editor focus stop") { $0.textEntryFocus(.textEditor) }
            let content = "FIRST-abcdefghijklmnopqrstuvwxyz-0123456789\nSECOND\nTHIRD\nFOURTH\nFIFTH\nLAST"
            session.send(.paste(.init(content: content)))
            let pasted = try await recorder.wait(description: "multiline paste retained exactly with final caret visible") {
                $0.textEntryEditor?.control?.value == .text(content) && $0.textEntryContains("LAST")
            }
            #expect(!pasted.textEntryContains("FIRST-"))
            #expect(pasted.textEntryContains("Submits=0"))
            expectVisibleCaret(pasted)
            session.send(.key(.return))
            let newline = try await recorder.wait(description: "editor Return inserts newline without submission") {
                $0.textEntryEditor?.control?.value == .text(content + "\n")
            }
            #expect(newline.textEntryContains("Submits=0"))
            session.send(.key(.backspace))
            _ = try await recorder.wait(description: "native backspace removes newline") {
                $0.textEntryEditor?.control?.value == .text(content)
            }
            session.send(.key(.arrowLeft, modifiers: .shift))
            _ = try await recorder.wait(description: "native selection covers final character") {
                $0.textEntryEditor?.textInput?.selection == (content.utf16.count - 1)..<content.utf16.count
            }
            session.send(.key(.character("!")))
            let replaced = String(content.dropLast()) + "!"
            _ = try await recorder.wait(description: "typing replaces the selected character") {
                $0.textEntryEditor?.control?.value == .text(replaced)
            }
            surface.updateSurfaceSize(.init(width: 24, height: 16))
            session.requestSurfaceRefresh()
            let resized = try await recorder.wait(description: "narrow resize retains editor and text") {
                $0.raster.size.width == 24 && $0.textEntryFocus(.textEditor)
                    && $0.textEntryEditor?.control?.value == .text(replaced)
            }
            #expect(resized.focusedIdentity == pasted.focusedIdentity)
            expectVisibleCaret(resized)
            // Native movement follows visual rows, including the wrapped first line.
            for _ in 0..<12 { session.send(.key(.arrowUp)) }
            let top = try await recorder.wait(description: "caret movement scrolls the first wrapped line into view") {
                $0.textEntryContains("FIRST-") && ($0.textEntryEditor?.textInput?.insertionOffset ?? 999) < 20
            }
            #expect(top.textEntryEditor?.control?.value == .text(replaced))
            let clusters = try #require(top.textEntryEditor?.textInput?.clusters)
            #expect(Set(clusters.prefix(42).map { $0.rect.origin.y }).count > 1)
            expectVisibleCaret(top)
            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(description: "theme retains native editor caret and text") {
                $0.textEntryContains("Light=true") && $0.textEntryFocus(.textEditor)
            }
            #expect(themed.textEntryEditor?.textInput?.insertionOffset == top.textEntryEditor?.textInput?.insertionOffset)
            session.send(.key(.tab))
            _ = try await recorder.wait(description: "Tab skips editor's private scrolling surface") { $0.textEntryFocus(.button) }
            session.send(.key(.tab, modifiers: .shift))
            _ = try await recorder.wait(description: "Shift-Tab returns to editor") { $0.textEntryFocus(.textEditor) }
        }
    }

    private func expectVisibleCaret(_ frame: SemanticHostFrame) {
        guard let node = frame.textEntryEditor, let caret = node.cursorAnchor else {
            Issue.record("Expected a native editor caret")
            return
        }
        #expect(caret.y >= node.rect.origin.y)
        #expect(caret.y < node.rect.origin.y + node.rect.size.height)
        #expect(caret.x >= node.rect.origin.x)
        #expect(caret.x < node.rect.origin.x + node.rect.size.width)
    }
}

@MainActor
private func withTextEntry(_ body: (HostedSceneSession, HostedRasterSurface, HostedFrameRecorder) async throws -> Void) async throws {
    let recorder = HostedFrameRecorder()
    let surface = HostedRasterSurface(surfaceSize: .init(width: 60, height: 16), appearance: .fallback, onFrame: { frame in
        // Inspect every delivered frame, including focus and submission transitions.
        #expect(!frame.raster.lines.joined().contains("Synthetic-"))
        #expect(!String(reflecting: frame.semantics).contains("Synthetic-"))
        for node in frame.semantics.accessibilityNodes where node.role == .secureField {
            #expect(node.textInput == nil)
            #expect(node.control?.value == nil)
        }
        recorder.receive(frame)
    })
    let session = try HostedSceneSession(for: TextEntryTestApp(), sceneID: "text-entry", surface: surface)
    let run = Task { try await session.start() }
    do {
        try await body(session, surface, recorder)
        session.stop()
        #expect(try await run.value == .inputEnded)
    } catch {
        session.stop()
        _ = await run.result
        throw error
    }
}

private struct TextEntryTestApp { nonisolated init() {} }
extension TextEntryTestApp: App {
    var body: some Scene { WindowGroup(id: "text-entry") { TextEntryTestView() }.exitOnKeys([]) }
}

@MainActor
private struct TextEntryTestView {
    @State private var password = ""
    @State private var notes = ""
    @State private var enabled = true
    @State private var light = false
    @State private var submissions = 0
    @FocusState private var passwordFocused: Bool
}

extension TextEntryTestView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SecureField("Demo password", text: $password).focused($passwordFocused).disabled(!enabled)
            TextEditor(text: $notes).frame(height: 6).disabled(!enabled)
            Button("Done") {}
            Text("Length=\(password.count) Submits=\(submissions)")
            Text("Light=\(light)")
        }
        .chioTheme(light ? .light : .default)
        .onSubmit { submissions += 1 }
        .onKeyPress { press in
            guard press.modifiers == .ctrl else { return .ignored }
            switch press.key {
            case .character("t"): light.toggle()
            case .character("d"):
                enabled.toggle()
                if enabled { passwordFocused = true }
            default: return .ignored
            }
            return .handled
        }
    }
}

private extension SemanticHostFrame {
    func textEntryContains(_ text: String) -> Bool { raster.lines.contains { $0.contains(text) } }
    func textEntryFocus(_ role: AccessibilityRole) -> Bool {
        semantics.accessibilityNodes.contains { $0.identity == focusedIdentity && $0.role == role }
    }
    var textEntryEditor: AccessibilityNode? { semantics.accessibilityNodes.first { $0.role == .textEditor } }
}
