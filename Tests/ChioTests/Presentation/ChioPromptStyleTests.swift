import Chio
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct ChioPromptStyleTests {
    @Test("Both native prompt kinds apply custom chrome and retain vertical actions at narrow widths",
          arguments: [false, true])
    func narrowCustomChrome(alert: Bool) throws {
        let theme = ChioTheme.default.replacing(colors: ChioTheme.default.colors.replacing(
            accent: Color(hexRGB: 0x123ABC), foreground: Color(hexRGB: 0xBACDEF),
            surface: Color(hexRGB: 0x182736), border: Color(hexRGB: 0x765432)
        ))
        let rendered = DefaultRenderer().render(
            PromptRenderFixture(alert: alert).chioTheme(theme)
                .environment(\.terminalSize, .init(width: 36, height: 18)),
            proposal: .init(width: 36, height: 18)
        )
        let text = rendered.rasterSurface.lines.joined(separator: "\n")
        #expect(text.contains("Local change"))
        #expect(text.contains("Keep the draft?"))
        #expect(text.contains("Cancel"))
        #expect(text.contains("Remove"))
        #expect(text.contains("Unavailable"))
        let cells = rendered.rasterSurface.cells.flatMap { $0 }
        #expect(cells.contains { $0.character == "╭" && $0.style?.foregroundColor == theme.colors.accent })
        let prose = try #require(cells.first { $0.character == "K" })
        #expect(prose.style?.foregroundColor == theme.colors.foreground)
        #expect(prose.style?.backgroundColor == theme.colors.surface)
        #expect(rendered.diagnostics.runtime.issues.isEmpty)
        #expect(rendered.semanticSnapshot.accessibilityNodes.contains {
            $0.role == (alert ? .alert : .confirmationDialog)
        })
        let unavailable = try #require(rendered.semanticSnapshot.accessibilityNodes.first {
            $0.role == .button && $0.label == "Unavailable"
        })
        #expect(!unavailable.isEnabled)
        #expect(!rendered.semanticSnapshot.focusRegions.contains { $0.identity == unavailable.identity })
        let cancelRow = try #require(rendered.rasterSurface.lines.firstIndex { $0.contains("Cancel") })
        let removeRow = try #require(rendered.rasterSurface.lines.firstIndex { $0.contains("Remove") })
        #expect(removeRow > cancelRow)
    }

    @Test("Native prompts retain their default dismissal actions", arguments: [false, true])
    func defaultDismissalAction(alert: Bool) {
        let rendered: RenderSnapshot
        if alert {
            rendered = DefaultRenderer().render(
                Text("Workspace").alert("Notice", isPresented: .constant(true)).chioTheme(.default),
                proposal: .init(width: 36, height: 18)
            )
        } else {
            rendered = DefaultRenderer().render(
                Text("Workspace").confirmationDialog("Notice", isPresented: .constant(true)).chioTheme(.default),
                proposal: .init(width: 36, height: 18)
            )
        }
        #expect(rendered.rasterSurface.lines.contains { $0.contains(alert ? "Dismiss" : "Cancel") })
        #expect(rendered.diagnostics.runtime.issues.isEmpty)
    }

    @Test("Confirm, Cancel and Escape restore the editor with its retained draft",
          arguments: [false, true], ["Remove", "Cancel", "Escape"])
    func nativeDismissalAndFocusRestoration(alert: Bool, action: String) async throws {
        try await withPromptScene(alert: alert) { session, recorder in
            _ = try await recorder.wait(description: "background editor initially focused") { $0.promptFocus("Draft") }
            session.sendInput(Array("Retained draft".utf8))
            let before = try await recorder.wait(description: "background draft edited") {
                $0.promptFocus("Draft") && $0.promptContains("Retained draft")
            }
            session.send(.key(.character("k"), modifiers: .ctrl))
            let opened = try await recorder.wait(after: before.sequence, description: "native prompt takes focus") {
                $0.promptIsPresented && $0.focusedIdentity != nil && $0.focusedIdentity != before.focusedIdentity
            }
            let unavailable = try #require(opened.semantics.accessibilityNodes.first {
                $0.role == .button && $0.label == "Unavailable"
            })
            #expect(!unavailable.isEnabled)
            #expect(!opened.semantics.focusRegions.contains { $0.identity == unavailable.identity })
            #expect(!opened.semantics.focusRegions.contains { $0.identity == before.focusedIdentity })

            let activated: SemanticHostFrame
            if action == "Escape" {
                activated = opened
                session.send(.key(.escape))
            } else {
                activated = try await focusPromptAction(action, from: opened, session: session, recorder: recorder)
                if action == "Remove" {
                    #expect(activated.raster.cells.flatMap { $0 }.contains {
                        $0.style?.foregroundColor == ChioTheme.default.colors.error
                    })
                }
                session.send(.key(.return))
            }
            let restored = try await recorder.wait(after: activated.sequence, description: "dismissal restores the draft editor") {
                !$0.promptIsPresented && $0.focusedIdentity == before.focusedIdentity
                    && $0.promptContains("Dismissed=1")
            }
            #expect(restored.promptContains("Retained draft"))
            #expect(restored.promptContains(action == "Remove" ? "Removed=1" : "Removed=0"))
            #expect(restored.promptContains("Unavailable=0"))
            session.send(.key(.character("!")))
            _ = try await recorder.wait(after: restored.sequence, description: "restored native editor accepts input") {
                $0.promptContains("Retained draft!") && $0.promptFocus("Draft")
            }
        }
    }
}

@MainActor
private struct PromptRenderFixture {
    let alert: Bool
}

extension PromptRenderFixture: View {
    @ViewBuilder var body: some View {
        if alert {
            Text("Workspace").alert("Local change", isPresented: .constant(true)) {
                actions
            } message: { Text("Keep the draft?") }
        } else {
            Text("Workspace").confirmationDialog("Local change", isPresented: .constant(true)) {
                actions
            } message: { Text("Keep the draft?") }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {}
            Button("Unavailable", role: .confirm) {}.disabled(true)
        }
    }
}

private struct PromptTestApp {
    let alert: Bool
    nonisolated init() { alert = false }
    nonisolated init(alert: Bool) { self.alert = alert }
}

extension PromptTestApp: App {
    var body: some Scene {
        WindowGroup(id: "prompt-tests") { PromptTestView(alert: alert) }.exitOnKeys([])
    }
}

@MainActor
private struct PromptTestView {
    let alert: Bool
    @State private var draft = ""
    @State private var presented = false
    @State private var removed = 0
    @State private var dismissed = 0
    @State private var unavailable = 0
    @FocusState private var editorFocused: Bool
}

extension PromptTestView: View {
    var body: some View {
        promptContent
            .chioTheme(.default)
            .defaultFocus($editorFocused, true)
            .onKeyPress { press in
                guard press == KeyPress(.character("k"), modifiers: .ctrl), !presented else { return .ignored }
                presented = true
                return .handled
            }
    }

    @ViewBuilder private var promptContent: some View {
        if alert {
            content.alert("Local change", isPresented: $presented, onDismiss: { dismissed += 1 }) {
                actions
            } message: { Text("Keep the draft?") }
        } else {
            content.confirmationDialog("Local change", isPresented: $presented, onDismiss: { dismissed += 1 }) {
                actions
            } message: { Text("Keep the draft?") }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Draft", text: $draft).focused($editorFocused)
            Text("Removed=\(removed) Dismissed=\(dismissed)")
            Text("Unavailable=\(unavailable)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Cancel", role: .cancel) { presented = false }
            Button("Remove", role: .destructive) {
                removed += 1
                presented = false
            }
            Button("Unavailable", role: .confirm) { unavailable += 1 }.disabled(true)
        }
    }
}

@MainActor
private func withPromptScene(
    alert: Bool,
    perform: (HostedSceneSession, HostedFrameRecorder) async throws -> Void
) async throws {
    let recorder = HostedFrameRecorder()
    let surface = HostedRasterSurface(surfaceSize: .init(width: 36, height: 18), appearance: .fallback,
                                     onFrame: { recorder.receive($0) })
    let session = try HostedSceneSession(for: PromptTestApp(alert: alert), sceneID: "prompt-tests", surface: surface)
    let run = Task { try await session.start() }
    do {
        try await perform(session, recorder)
        session.stop()
        #expect(try await run.value == .inputEnded)
    } catch {
        session.stop()
        _ = await run.result
        throw error
    }
}

@MainActor
private func focusPromptAction(
    _ label: String, from initial: SemanticHostFrame,
    session: HostedSceneSession, recorder: HostedFrameRecorder
) async throws -> SemanticHostFrame {
    var frame = initial
    for _ in 0...initial.semantics.focusRegions.count {
        if frame.promptFocus(label) { return frame }
        let previous = frame
        session.send(.key(.tab))
        frame = try await recorder.wait(after: previous.sequence, description: "Tab advances inside native prompt") {
            $0.promptIsPresented && $0.focusedIdentity != previous.focusedIdentity
        }
    }
    throw PromptActionNotFocused(label: label)
}

private struct PromptActionNotFocused: Error {
    let label: String
}

private extension SemanticHostFrame {
    func promptContains(_ text: String) -> Bool { raster.lines.contains { $0.contains(text) } }
    func promptFocus(_ label: String) -> Bool {
        semantics.accessibilityNodes.contains { $0.identity == focusedIdentity && $0.label == label }
    }
    var promptIsPresented: Bool {
        semantics.accessibilityNodes.contains { $0.role == .alert || $0.role == .confirmationDialog }
    }
}
