import Chio
import SwiftTUIRuntime
import Testing

@MainActor
struct MarkdownTableInteractionTests {
    @Test("Nested report and table scroll views preserve navigation through theme and resize")
    func horizontalScrolling() async throws {
        let recorder = HostedFrameRecorder()
        let surface = HostedRasterSurface(
            surfaceSize: .init(width: 20, height: 12), appearance: .fallback,
            onFrame: { recorder.receive($0) }
        )
        let session = try HostedSceneSession(for: TableTestApp(), sceneID: "markdown-table", surface: surface)
        let run = Task { try await session.start() }
        defer { session.stop() }
        do {
            let outer = try await recorder.wait(description: "report vertical scroll receives requested native focus") { frame in
                frame.semantics.accessibilityNodes.contains {
                    $0.identity == frame.focusedIdentity
                        && ($0.role == .scrollView || $0.role == .scrollViewWithIndicators)
                        && $0.label == "Table report"
                } && frame.raster.lines.contains { $0.contains("FIRST") }
            }
            session.send(.key(.tab))
            let initial = try await recorder.wait(after: outer.sequence, description: "Tab reaches the table horizontal scroll") {
                self.hasScrollFocus($0) && $0.focusedIdentity != outer.focusedIdentity
                    && $0.raster.lines.contains { $0.contains("FIRST") }
            }
            #expect(!initial.raster.lines.contains { $0.contains("LAST") })
            #expect(initial.raster.lines.contains { $0.contains("After table") })
            session.send(.key(.end))
            let end = try await recorder.wait(after: initial.sequence, description: "End reveals the last column") {
                $0.raster.lines.contains { $0.contains("LAST") }
            }
            #expect(end.focusedIdentity == initial.focusedIdentity)
            #expect(!end.raster.lines.contains { $0.contains("FIRST") })
            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(after: end.sequence, description: "theme preserves table offset") {
                $0.raster.lines.contains { $0.contains("Theme=light") }
                    && $0.raster.lines.contains { $0.contains("LAST") }
            }
            #expect(themed.focusedIdentity == end.focusedIdentity)
            surface.updateSurfaceSize(.init(width: 16, height: 12))
            session.requestSurfaceRefresh()
            let resized = try await recorder.wait(after: themed.sequence, description: "resize retains the table's focus") {
                $0.raster.size.width == 16 && self.hasScrollFocus($0)
            }
            #expect(resized.focusedIdentity == themed.focusedIdentity)
            session.send(.key(.home))
            let home = try await recorder.wait(after: resized.sequence, description: "Home restores the first column") {
                $0.raster.lines.contains { $0.contains("FIRST") }
            }
            #expect(home.focusedIdentity == initial.focusedIdentity)
            #expect(home.raster.lines.contains { $0.contains("After table") })
            session.send(.key(.tab, modifiers: .shift))
            let returned = try await recorder.wait(after: home.sequence, description: "Shift-Tab restores exact vertical report focus") {
                $0.focusedIdentity == outer.focusedIdentity && self.hasScrollFocus($0)
            }
            session.send(.key(.arrowDown))
            let stepped = try await recorder.wait(after: returned.sequence, description: "Down scrolls the outer report vertically") {
                $0.raster.lines != returned.raster.lines
            }
            #expect(stepped.focusedIdentity == outer.focusedIdentity)
            #expect(stepped.raster.lines.contains { $0.contains("Theme=light") })
            session.stop()
            #expect(try await run.value == .inputEnded)
        } catch {
            session.stop()
            _ = await run.result
            throw error
        }
    }

    private func hasScrollFocus(_ frame: SemanticHostFrame) -> Bool {
        frame.semantics.accessibilityNodes.contains {
            $0.identity == frame.focusedIdentity
                && ($0.role == .scrollView || $0.role == .scrollViewWithIndicators)
        }
    }
}

private struct TableTestApp {
    nonisolated init() {}
}

extension TableTestApp: App {
    var body: some Scene {
        WindowGroup(id: "markdown-table") { TableTestView() }.exitOnKeys([])
    }
}

@MainActor
private struct TableTestView {
    @State private var light = false
    @FocusState private var isReading: Bool
    private let document = MarkdownDocument("""
    | First | Middle column with wide content | Last |
    | --- | --- | ---: |
    | FIRST | content | LAST |

    After table

    Tail 1

    Tail 2

    Tail 3

    Tail 4

    Tail 5

    Tail 6

    Tail 7

    Tail 8
    """)
}

extension TableTestView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Theme=\(light ? "light" : "dark")")
            ScrollView {
                MarkdownView(document)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .focused($isReading)
            .accessibilityLabel("Table report")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .chioTheme(light ? .light : .default)
        .onAppear { isReading = true }
        .onKeyPress { press in
            guard press == KeyPress(.character("t"), modifiers: .ctrl) else { return .ignored }
            light.toggle()
            return .handled
        }
    }
}
