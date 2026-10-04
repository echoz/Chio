import Chio
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct KeyHintsInteractionTests {
    @Test("Hosted hints update whole labels and positions through content, spacing, and resize changes")
    func contentThemeAndResizeReflow() async throws {
        try await withHintScene { session, surface, recorder in
            let initial = try await recorder.wait(description: "initial short hints with two-cell spacing") {
                $0.focusedIdentity != nil
                    && $0.raster.lines.contains { $0.contains("Phase=0 Gap=2") }
            }
            #expect(visibleLines(initial) == ["Phase=0 Gap=2", "q quit  / search"])

            session.send(.key(.character("e"), modifiers: .ctrl))
            let expanded = try await recorder.wait(after: initial.sequence, description: "longer label and additional hint") {
                $0.raster.lines.contains { $0.contains("Phase=1 Gap=2") }
            }
            #expect(visibleLines(expanded) == [
                "Phase=1 Gap=2", "q quit application  / search  r run",
            ])

            session.send(.key(.character("g"), modifiers: .ctrl))
            let spaced = try await recorder.wait(after: expanded.sequence, description: "theme spacing changes to four cells") {
                $0.raster.lines.contains { $0.contains("Phase=2 Gap=4") }
            }
            #expect(visibleLines(spaced) == [
                "Phase=2 Gap=4", "q quit application    / search    r run",
            ])

            surface.updateSurfaceSize(.init(width: 24, height: 6))
            session.requestSurfaceRefresh()
            let narrow = try await recorder.wait(after: spaced.sequence, description: "narrow hints wrap into two complete rows") {
                $0.raster.size.width == 24
            }
            #expect(visibleLines(narrow) == [
                "Phase=2 Gap=4", "q quit application", "/ search    r run",
            ])

            session.send(.key(.character("e"), modifiers: .ctrl))
            let collapsed = try await recorder.wait(after: narrow.sequence, description: "shorter label and removed hint return to one row") {
                $0.raster.lines.contains { $0.contains("Phase=3 Gap=4") }
            }
            #expect(visibleLines(collapsed) == ["Phase=3 Gap=4", "q quit    / search"])

            session.send(.key(.character("e"), modifiers: .ctrl))
            let expandedAgain = try await recorder.wait(after: collapsed.sequence, description: "expanded hints wrap again at the current width") {
                $0.raster.lines.contains { $0.contains("Phase=4 Gap=4") }
            }
            #expect(visibleLines(expandedAgain) == [
                "Phase=4 Gap=4", "q quit application", "/ search    r run",
            ])

            surface.updateSurfaceSize(.init(width: 40, height: 6))
            session.requestSurfaceRefresh()
            let wideAgain = try await recorder.wait(after: expandedAgain.sequence, description: "widening rejoins the hints with current spacing") {
                $0.raster.size.width == 40
            }
            #expect(visibleLines(wideAgain) == [
                "Phase=4 Gap=4", "q quit application    / search    r run",
            ])
        }
    }
}

private struct HintTestApp {
    nonisolated init() {}
}

extension HintTestApp: App {
    var body: some Scene {
        WindowGroup(id: "hint-tests") { HintTestView() }
            .exitOnKeys([])
    }
}

@MainActor
private struct HintTestView {
    @State private var expanded = false
    @State private var widerGap = false
    @State private var phase = 0
    @FocusState private var focused: Bool

    private var theme: ChioTheme {
        var theme = ChioTheme.default
        theme.spacing = .init(hintGap: widerGap ? 4 : 2)
        return theme
    }
}

extension HintTestView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Phase=\(phase) Gap=\(widerGap ? 4 : 2)")
            KeyHints {
                KeyHint("q", expanded ? "quit application" : "quit")
                KeyHint("/", "search")
                if expanded { KeyHint("r", "run") }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .chioTheme(theme)
        .focusable()
        .focused($focused)
        .defaultFocus($focused, true)
        .focusEffectDisabled()
        .onKeyPress { press in
            if press == KeyPress(.character("e"), modifiers: .ctrl) {
                expanded.toggle()
                phase += 1
                return .handled
            }
            if press == KeyPress(.character("g"), modifiers: .ctrl) {
                widerGap.toggle()
                phase += 1
                return .handled
            }
            return .ignored
        }
    }
}

@MainActor
private func withHintScene(
    perform: @MainActor (HostedSceneSession, HostedRasterSurface, HostedFrameRecorder) async throws -> Void
) async throws {
    let recorder = HostedFrameRecorder()
    let surface = HostedRasterSurface(
        surfaceSize: .init(width: 40, height: 6),
        appearance: .fallback,
        onFrame: { recorder.receive($0) }
    )
    let session = try HostedSceneSession(for: HintTestApp(), sceneID: "hint-tests", surface: surface)
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

private func visibleLines(_ frame: SemanticHostFrame) -> [String] {
    var lines = frame.raster.lines.map {
        String($0.reversed().drop(while: { $0 == " " }).reversed())
    }
    while lines.last == "" { lines.removeLast() }
    return lines
}
