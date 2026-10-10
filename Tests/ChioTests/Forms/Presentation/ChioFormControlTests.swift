import Chio
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct ChioFormControlTests {
    @Test("Styled native controls retain arrows, Tab, activation, and theme switching")
    func nativeInput() async throws {
        let recorder = HostedFrameRecorder()
        let surface = HostedRasterSurface(
            surfaceSize: .init(width: 60, height: 12), appearance: .fallback,
            onFrame: { recorder.receive($0) }
        )
        let session = try HostedSceneSession(for: FormControlTestApp(),
                                            sceneID: "form-controls", surface: surface)
        let run = Task { try await session.start() }
        defer { session.stop() }
        do {
            let initial = try await recorder.wait(description: "native picker owns initial focus") {
                $0.hasFocusedPicker && $0.containsFormText("Model=s Confirm=false")
            }
            #expect(initial.raster.cells.flatMap { $0 }.contains {
                $0.character == "▌" && $0.style?.foregroundColor == ChioTheme.default.colors.accent
            })
            session.send(.key(.arrowRight))
            _ = try await recorder.wait(after: initial.sequence, description: "native picker steps right") {
                $0.hasFocusedPicker && $0.containsFormText("Model=l Confirm=false")
            }
            session.send(.key(.tab))
            _ = try await recorder.wait(description: "Tab reaches the single native toggle") {
                $0.hasFocusedToggle
            }
            session.send(.key(.return))
            _ = try await recorder.wait(description: "native toggle activation changes binding") {
                $0.hasFocusedToggle && $0.containsFormText("Model=l Confirm=true")
            }
            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(description: "theme preserves native focus and values") {
                $0.hasFocusedToggle && $0.containsFormText("Model=l Confirm=true Theme=light")
            }
            #expect(themed.raster.cells.flatMap { $0 }.contains {
                $0.character == "▌" && $0.style?.foregroundColor == ChioTheme.light.colors.accent
            })
            session.send(.key(.tab, modifiers: .shift))
            _ = try await recorder.wait(description: "Shift-Tab returns to native picker") {
                $0.hasFocusedPicker
            }
            session.send(.key(.arrowUp))
            _ = try await recorder.wait(description: "native picker steps up after theme switch") {
                $0.hasFocusedPicker && $0.containsFormText("Model=s Confirm=true Theme=light")
            }
            session.stop()
            #expect(try await run.value == .inputEnded)
        } catch {
            session.stop()
            _ = await run.result
            throw error
        }
    }
}

private struct FormControlTestApp {
    nonisolated init() {}
}

extension FormControlTestApp: App {
    var body: some Scene {
        WindowGroup(id: "form-controls") { FormControlTestView() }.exitOnKeys([])
    }
}

@MainActor
private struct FormControlTestView {
    private enum Field: Hashable { case model, confirm }
    @State private var model = "s"
    @State private var confirm = false
    @State private var light = false
    @FocusState private var focusedField: Field?
}

extension FormControlTestView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            FormField("Model") {
                Picker("Model", selection: $model) {
                    Text("Small").tag("s")
                    Text("Large").tag("l")
                }.focused($focusedField, equals: .model)
            }
            FormField("Confirm") {
                Toggle("Confirm", isOn: $confirm).focused($focusedField, equals: .confirm)
            }
            Text("Model=\(model) Confirm=\(confirm) Theme=\(light ? "light" : "dark")")
        }
        .chioTheme(light ? .light : .default)
        .onKeyPress { press in
            guard press == KeyPress(.character("t"), modifiers: .ctrl) else { return .ignored }
            light.toggle()
            return .handled
        }
    }
}

private extension SemanticHostFrame {
    var hasFocusedPicker: Bool {
        semantics.accessibilityNodes.contains { $0.identity == focusedIdentity && $0.role == .picker }
    }
    var hasFocusedToggle: Bool {
        semantics.accessibilityNodes.contains { $0.identity == focusedIdentity && $0.role == .toggle }
    }
    func containsFormText(_ text: String) -> Bool {
        raster.lines.contains { $0.contains(text) }
    }
}
