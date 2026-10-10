import Chio
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct ChioToastStyleTests {
    @Test("Native toast declarations retain each semantic tone and theme through hosting",
          arguments: TerminalTone.allCases, [ChioTheme.default, .light])
    func semanticTone(tone: TerminalTone, theme: ChioTheme) throws {
        let size = CellSize(width: 36, height: 18)
        let rendered = DefaultRenderer().render(
            Text("Base").frame(width: size.width, height: size.height)
                .toast("Local feedback", isPresented: .constant(true), style: ChioToastStyle(theme: theme, tone: tone), duration: nil)
                .chioTheme(theme).environment(\.terminalSize, size),
            proposal: ProposedViewSize(width: size.width, height: size.height)
        )
        let icon: Character
        let color: Color
        switch tone {
        case .accent, .info: icon = "ℹ"; color = theme.colors.accent
        case .success: icon = "✓"; color = theme.colors.success
        case .warning: icon = "⚠"; color = theme.colors.warning
        case .danger: icon = "✗"; color = theme.colors.error
        case .neutral: icon = "·"; color = theme.colors.secondaryText
        }
        let cells = rendered.rasterSurface.cells.flatMap { $0 }
        let iconCell = try #require(cells.first { $0.character == icon })
        #expect(iconCell.style?.foregroundColor == color)
        #expect(cells.contains { $0.character == "╭" && $0.style?.foregroundColor == color })
        #expect(rendered.rasterSurface.lines.joined(separator: "\n").contains("Local feedback"))
        #expect(rendered.semanticSnapshot.focusRegions.isEmpty)
    }

    @Test("Toast message and compact chrome remain visible at supported terminal sizes",
          arguments: [CellSize(width: 36, height: 18), CellSize(width: 50, height: 30),
                      CellSize(width: 100, height: 30)])
    func compactLayout(size: CellSize) {
        let rendered = DefaultRenderer().render(
            Text("Base").frame(width: size.width, height: size.height)
                .toast("Local feedback", isPresented: .constant(true), style: ChioToastStyle(tone: .success), duration: nil)
                .chioTheme(.default).environment(\.terminalSize, size),
            proposal: ProposedViewSize(width: size.width, height: size.height)
        )
        let text = rendered.rasterSurface.lines.joined(separator: "\n")
        #expect(rendered.rasterSurface.size == size)
        #expect(text.contains("Local feedback"))
        #expect(text.contains("✓") && text.contains("╭") && text.contains("╰"))
        #expect(rendered.semanticSnapshot.focusRegions.isEmpty)
    }

    @Test("Custom severity colors reach hosted toast icon, border and background")
    func customTheme() throws {
        let size = CellSize(width: 36, height: 18)
        let errorColor = Color(hexRGB: 0x123456)
        let surfaceColor = Color(hexRGB: 0x192837)
        let theme = ChioTheme.default.replacing(colors: ChioTheme.default.colors.replacing(
            surface: surfaceColor, error: errorColor
        ))
        let rendered = DefaultRenderer().render(
            Text("Base").frame(width: size.width, height: size.height)
                .toast("Local feedback", isPresented: .constant(true), style: ChioToastStyle(theme: theme, tone: .danger), duration: nil)
                .chioTheme(theme).environment(\.terminalSize, size),
            proposal: ProposedViewSize(width: size.width, height: size.height)
        )
        let cells = rendered.rasterSurface.cells.flatMap { $0 }
        let icon = try #require(cells.first { $0.character == "✗" })
        #expect(icon.style?.foregroundColor == errorColor)
        #expect(icon.style?.backgroundColor == surfaceColor)
        #expect(cells.contains { $0.character == "╭" && $0.style?.foregroundColor == errorColor })
    }

    @Test("A timed native toast leaves editing focus intact and reports dismissal")
    func timedLifecycle() async throws {
        try await withToastScene(timed: true) { session, _, recorder in
            let visible = try await recorder.wait(description: "timed toast with native field focus") {
                $0.toastContains("Local feedback") && $0.toastEditorFocused
            }
            session.sendInput(Array("draft".utf8))
            let edited = try await recorder.wait(description: "toast permits native editing") { $0.toastQuery("draft") }
            #expect(edited.focusedIdentity == visible.focusedIdentity)
            let dismissed = try await recorder.wait(description: "native deadline clears toast and calls onDismiss") {
                $0.toastContains("Dismissed=1") && !$0.toastContains("Local feedback")
            }
            #expect(dismissed.toastQuery("draft"))
            #expect(dismissed.focusedIdentity == visible.focusedIdentity)
        }
    }

    @Test("Explicit native dismissal preserves draft, focus, and theme through narrow resize")
    func explicitLifecycle() async throws {
        try await withToastScene(timed: false) { session, surface, recorder in
            let visible = try await recorder.wait(description: "persistent toast with native field focus") {
                $0.toastContains("Local feedback") && $0.toastEditorFocused
            }
            session.sendInput(Array("draft".utf8))
            _ = try await recorder.wait(description: "draft edited under persistent toast") { $0.toastQuery("draft") }
            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(after: visible.sequence, description: "toast updates theme without taking focus") {
                $0.raster.cells != visible.raster.cells && $0.toastContains("Light=true") && $0.toastContains("Local feedback")
            }
            #expect(themed.focusedIdentity == visible.focusedIdentity)
            surface.updateSurfaceSize(CellSize(width: 36, height: 18))
            session.requestSurfaceRefresh()
            let resized = try await recorder.wait(after: themed.sequence, description: "toast remains readable after narrow resize") {
                $0.raster.size == CellSize(width: 36, height: 18) && $0.toastContains("Local feedback")
            }
            #expect(resized.toastQuery("draft"))
            #expect(resized.focusedIdentity == visible.focusedIdentity)
            session.send(.key(.character("d"), modifiers: .ctrl))
            let dismissed = try await recorder.wait(description: "binding dismissal calls onDismiss once") {
                $0.toastContains("Dismissed=1") && !$0.toastContains("Local feedback")
            }
            #expect(dismissed.toastQuery("draft"))
            #expect(dismissed.focusedIdentity == visible.focusedIdentity)
        }
    }
}

private struct ToastTestApp {
    let timed: Bool
    nonisolated init() { timed = false }
    nonisolated init(timed: Bool) { self.timed = timed }
}

extension ToastTestApp: App {
    var body: some Scene {
        WindowGroup(id: "chio-toast-tests") { ToastTestView(timed: timed) }.exitOnKeys([])
    }
}

@MainActor
private struct ToastTestView {
    let timed: Bool
    @State private var query = ""
    @State private var isPresented = true
    @State private var dismissed = 0
    @State private var light = false
    @FocusState private var editing: Bool
    @Environment(\.terminalSize) private var terminalSize
}

extension ToastTestView: View {
    var body: some View {
        let theme: ChioTheme = light ? .light : .default
        VStack(alignment: .leading) {
            Text("Dismissed=\(dismissed) Light=\(light)")
            TextField("Draft", text: $query).focused($editing)
            Spacer(minLength: 0)
        }
        .frame(width: terminalSize.width, height: terminalSize.height)
        .toast("Local feedback", isPresented: $isPresented,
               style: ChioToastStyle(theme: theme, tone: .success), duration: timed ? 1 : nil,
               onDismiss: { dismissed += 1 })
        .chioTheme(theme)
        .onAppear { editing = true }
        .onKeyPress { press in
            guard press.modifiers == .ctrl else { return .ignored }
            switch press.key {
            case .character("t"): light.toggle()
            case .character("d"): isPresented = false
            default: return .ignored
            }
            return .handled
        }
    }
}

@MainActor
private func withToastScene(
    timed: Bool,
    perform: @MainActor (HostedSceneSession, HostedRasterSurface, HostedFrameRecorder) async throws -> Void
) async throws {
    let recorder = HostedFrameRecorder()
    let surface = HostedRasterSurface(surfaceSize: CellSize(width: 60, height: 20), appearance: .fallback,
                                      onFrame: { recorder.receive($0) })
    let session = try HostedSceneSession(for: ToastTestApp(timed: timed), sceneID: "chio-toast-tests", surface: surface)
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
    func toastContains(_ text: String) -> Bool { raster.lines.contains { $0.contains(text) } }
    var toastEditorFocused: Bool {
        semantics.accessibilityNodes.contains { $0.role == .textField && $0.identity == focusedIdentity }
    }
    func toastQuery(_ value: String) -> Bool {
        semantics.accessibilityNodes.contains { $0.role == .textField && $0.control?.value == .text(value) }
    }
}
