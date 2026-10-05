@testable import ChioDashboard
import Chio
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct PaginationExampleTests {
    @Test("History keeps its first page, controls and hints across themes and sizes",
          arguments: [CellSize(width: 100, height: 30), CellSize(width: 50, height: 30),
                      CellSize(width: 36, height: 18)], [false, true])
    func layout(size: CellSize, light: Bool) {
        let rendered = DefaultRenderer().render(
            PaginationExampleView(light: light).environment(\.terminalSize, size),
            proposal: .init(width: size.width, height: size.height), frameInstant: .zero
        )
        let text = rendered.rasterSurface.lines.joined(separator: "\n")
        #expect(rendered.rasterSurface.size == size)
        #expect(text.contains("/ run history"))
        #expect(text.contains("Build 01") && text.contains("Passed"))
        #expect(text.contains("1 / 8") && text.contains("1–3 of 23"))
        #expect(text.contains("Rows per page") && text.contains("^Q quit"))
        #expect(rendered.semanticSnapshot.accessibilityNodes.contains { $0.role == .button && $0.label == "Next page" && $0.isEnabled })
        #expect(rendered.semanticSnapshot.accessibilityNodes.contains { $0.role == .button && $0.label == "Previous page" && !$0.isEnabled })
    }

    @Test("Filtering, page navigation, theme, resize and reset retain coherent history results")
    func historyWorkflow() async throws {
        try await withHistory { session, surface, recorder in
            _ = try await recorder.wait(description: "history search starts focused") { $0.historyFocused(.textField) }
            session.sendInput(Array("build".utf8))
            _ = try await recorder.wait(description: "filter resets to the first of two matching pages") {
                $0.historyQuery("build") && $0.historyContains("1 / 2") && $0.historyContains("1–3 of 6")
            }
            try await focusHistory(.button, label: "Next page", session: session, recorder: recorder)
            session.send(.key(.return))
            let last = try await recorder.wait(description: "native Next opens the last filtered page") {
                $0.historyContains("2 / 2") && $0.historyContains("4–6 of 6") && $0.historyContains("Build 13")
            }
            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(after: last.sequence, description: "theme retains the filtered page") {
                $0.raster.cells != last.raster.cells && $0.historyContains("2 / 2") && $0.historyQuery("build")
            }
            surface.updateSurfaceSize(.init(width: 36, height: 18))
            session.requestSurfaceRefresh()
            _ = try await recorder.wait(after: themed.sequence, description: "compact history retains page and filter") {
                $0.raster.size == CellSize(width: 36, height: 18)
                    && $0.historyContains("4–6 of 6") && $0.historyContains("^Q quit") && $0.historyQuery("build")
            }
            session.send(.key(.character("r"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "reset restores all history on its first page") {
                $0.historyQuery("") && $0.historyContains("1 / 8") && $0.historyContains("1–3 of 23")
            }
            try await focusHistory(.textField, session: session, recorder: recorder)
            session.sendInput(Array("zzzz".utf8))
            let empty = try await recorder.wait(description: "a no-match filter has no page and an explicit empty state") {
                $0.historyContains("No pages") && $0.historyContains("0 items") && $0.historyContains("No matching runs.")
            }
            #expect(empty.semantics.accessibilityNodes.filter { $0.role == .button }.allSatisfy { !$0.isEnabled })
            session.send(.key(.character("r"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "reset recovers from empty results") {
                $0.historyQuery("") && $0.historyContains("1 / 8") && $0.historyContains("Build 01")
            }
        }
    }

    @Test("Changing page size keeps the old first visible run within the new page")
    func pageSizeAnchor() async throws {
        try await withHistory { session, _, recorder in
            _ = try await recorder.wait(description: "history search ready") { $0.historyFocused(.textField) }
            try await focusHistory(.button, label: "Next page", session: session, recorder: recorder)
            session.send(.key(.end))
            _ = try await recorder.wait(description: "End opens the final three-row page") {
                $0.historyContains("8 / 8") && $0.historyContains("22–23 of 23") && $0.historyContains("Review 22")
            }
            try await focusHistory(.picker, session: session, recorder: recorder)
            session.send(.key(.arrowRight))
            _ = try await recorder.wait(description: "five-row pages keep run 22 visible") {
                $0.historyContains("5 / 5") && $0.historyContains("21–23 of 23") && $0.historyContains("Review 22")
            }
            try await focusHistory(.button, label: "Previous page", session: session, recorder: recorder)
            session.send(.key(.home))
            _ = try await recorder.wait(description: "Home returns to the first resized page") {
                $0.historyContains("1 / 5") && $0.historyContains("1–5 of 23") && $0.historyContains("Build 01")
            }
        }
    }
}

@MainActor
private func focusHistory(
    _ role: AccessibilityRole, label: String? = nil,
    session: HostedSceneSession, recorder: HostedFrameRecorder
) async throws {
    var frame = try await recorder.wait(description: "current history focus") { $0.focusedIdentity != nil }
    for _ in 0..<8 {
        if frame.historyFocused(role, label: label) { return }
        session.send(.key(.tab))
        frame = try await recorder.wait(after: frame.sequence, description: "native Tab advances history focus") { $0.focusedIdentity != nil }
    }
    Issue.record("Native focus did not reach \(role) / \(label ?? "any label")")
}

private struct HistoryTestApp {
    nonisolated init() {}
}

extension HistoryTestApp: App {
    var body: some Scene {
        WindowGroup(id: "history-tests") { PaginationExampleView() }.exitOnKeys([])
    }
}

@MainActor
private func withHistory(
    perform: @MainActor (HostedSceneSession, HostedRasterSurface, HostedFrameRecorder) async throws -> Void
) async throws {
    let recorder = HostedFrameRecorder()
    let surface = HostedRasterSurface(surfaceSize: .init(width: 100, height: 30), appearance: .fallback,
                                      onFrame: { recorder.receive($0) })
    let session = try HostedSceneSession(for: HistoryTestApp(), sceneID: "history-tests", surface: surface)
    let run = Task { try await session.start() }
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
    func historyContains(_ value: String) -> Bool { raster.lines.contains { $0.contains(value) } }
    func historyFocused(_ role: AccessibilityRole, label: String? = nil) -> Bool {
        semantics.accessibilityNodes.contains {
            $0.identity == focusedIdentity && $0.role == role && (label == nil || $0.label == label)
        }
    }
    func historyQuery(_ value: String) -> Bool {
        semantics.accessibilityNodes.contains { $0.role == .textField && $0.control?.value == .text(value) }
    }
}
