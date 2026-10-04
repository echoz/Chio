import Chio
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct MarkdownInteractionTests {
    @Test("Fenced code uses native horizontal End and Home and retains its offset through theme changes")
    func codeHorizontalScrolling() async throws {
        let recorder = HostedFrameRecorder()
        let surface = HostedRasterSurface(
            surfaceSize: .init(width: 20, height: 8),
            appearance: .fallback,
            onFrame: { recorder.receive($0) }
        )
        let session = try HostedSceneSession(
            for: MarkdownCodeTestApp(), sceneID: "markdown-code", surface: surface
        )
        let run = Task { try await session.start() }
        defer { session.stop() }
        do {
            let initial = try await recorder.wait(description: "native code scroll focus and first columns") {
                self.hasCodeFocus($0) && self.containsPrefix($0)
            }
            #expect(!initial.raster.lines.contains { $0.contains("-LAST") })
            expectAuthoredRows(initial)

            session.send(.key(.end))
            let end = try await recorder.wait(after: initial.sequence, description: "native End reveals the last code columns") {
                self.hasCodeFocus($0) && $0.raster.lines.contains { $0.contains("-LAST") }
            }
            #expect(end.focusedIdentity == initial.focusedIdentity)
            #expect(!containsPrefix(end))

            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(after: end.sequence, description: "theme changes while retaining the last code columns") {
                self.hasCodeFocus($0)
                    && $0.raster.lines.contains { $0.contains("Theme=light") }
                    && $0.raster.lines.contains { $0.contains("-LAST") }
            }
            #expect(themed.focusedIdentity == end.focusedIdentity)
            #expect(!containsPrefix(themed))

            session.send(.key(.home))
            let home = try await recorder.wait(after: themed.sequence, description: "native Home restores indentation and the first code columns") {
                self.hasCodeFocus($0) && self.containsPrefix($0)
            }
            #expect(home.focusedIdentity == themed.focusedIdentity)
            #expect(!home.raster.lines.contains { $0.contains("-LAST") })
            expectAuthoredRows(home)

            session.stop()
            #expect(try await run.value == .inputEnded)
        } catch {
            session.stop()
            _ = await run.result
            throw error
        }
    }

    private func hasCodeFocus(_ frame: SemanticHostFrame) -> Bool {
        frame.semantics.accessibilityNodes.contains {
            $0.identity == frame.focusedIdentity && $0.role == .scrollView
        }
    }

    private func containsPrefix(_ frame: SemanticHostFrame) -> Bool {
        // Four authored spaces plus the Markdown code surface's one-cell inset.
        frame.raster.lines.contains { $0.hasPrefix("     FIRST-") }
    }

    private func expectAuthoredRows(_ frame: SemanticHostFrame) {
        let lines = frame.raster.lines
        guard let first = lines.firstIndex(where: { $0.hasPrefix("     FIRST-") }),
              let second = lines.firstIndex(where: { $0.hasPrefix("     SECOND") }) else {
            Issue.record("Expected indented first and second code lines")
            return
        }
        #expect(second == first + 2)
        #expect(lines[first + 1].allSatisfy { $0 == " " })
    }
}

private struct MarkdownCodeTestApp {
    nonisolated init() {}
}

extension MarkdownCodeTestApp: App {
    var body: some Scene {
        WindowGroup(id: "markdown-code") { MarkdownCodeTestView() }
            .exitOnKeys([])
    }
}

@MainActor
private struct MarkdownCodeTestView {
    @State private var light = false
    private let document = MarkdownDocument(
        "```\n    FIRST-0123456789abcdefghijklmnop-LAST\n\n    SECOND\n```"
    )
}

extension MarkdownCodeTestView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Theme=\(light ? "light" : "dark")")
            MarkdownView(document)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .chioTheme(light ? .light : .default)
        .onKeyPress { press in
            guard press == KeyPress(.character("t"), modifiers: .ctrl) else { return .ignored }
            light.toggle()
            return .handled
        }
    }
}
