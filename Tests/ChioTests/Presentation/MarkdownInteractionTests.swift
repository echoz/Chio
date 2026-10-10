import Chio
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct MarkdownInteractionTests {
    @Test("Highlighted code retains native focus and offset through theme, paint, arrows, and resize")
    func codeHorizontalScrolling() async throws {
        let recorder = HostedFrameRecorder()
        let surface = HostedRasterSurface(
            surfaceSize: .init(width: 20, height: 10),
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

            session.send(.key(.arrowLeft))
            let left = try await recorder.wait(after: end.sequence, description: "left arrow moves one native code column") {
                self.hasCodeFocus($0) && $0.raster.lines != end.raster.lines
            }
            #expect(left.focusedIdentity == end.focusedIdentity)
            session.send(.key(.arrowRight))
            let right = try await recorder.wait(after: left.sequence, description: "right arrow restores the last columns") {
                self.hasCodeFocus($0) && $0.raster.lines == end.raster.lines
            }
            #expect(right.focusedIdentity == end.focusedIdentity)

            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(after: right.sequence, description: "theme changes while retaining the last code columns") {
                self.hasCodeFocus($0)
                    && $0.raster.lines.contains { $0.contains("Theme=light") }
                    && $0.raster.lines.contains { $0.contains("-LAST") }
            }
            #expect(themed.focusedIdentity == end.focusedIdentity)
            #expect(!containsPrefix(themed))

            session.send(.key(.character("p")))
            let plain = try await recorder.wait(after: themed.sequence, description: "plain paint preserves code focus and last columns") {
                self.hasCodeFocus($0) && $0.raster.lines.contains { $0.contains("Paint=plain") }
                    && $0.raster.lines.contains { $0.contains("-LAST") }
            }
            #expect(plain.focusedIdentity == themed.focusedIdentity)
            #expect(!containsPrefix(plain))
            session.send(.key(.character("p")))
            let automatic = try await recorder.wait(after: plain.sequence, description: "automatic paint restores syntax without moving the viewport") {
                self.hasCodeFocus($0) && $0.raster.lines.contains { $0.contains("Paint=auto") }
                    && $0.raster.lines.contains { $0.contains("-LAST") }
            }
            #expect(automatic.focusedIdentity == plain.focusedIdentity)
            #expect(automatic.raster.lines == themed.raster.lines)

            surface.updateSurfaceSize(.init(width: 16, height: 10))
            session.requestSurfaceRefresh()
            let resized = try await recorder.wait(after: automatic.sequence, description: "narrow resize retains code focus and the native offset") {
                self.hasCodeFocus($0) && $0.raster.size.width == 16
            }
            #expect(resized.focusedIdentity == automatic.focusedIdentity)
            if let row = automatic.raster.lines.firstIndex(where: { $0.contains("-LAST") }) {
                #expect(String(resized.raster.lines[row].prefix(12)) == String(automatic.raster.lines[row].prefix(12)))
            } else {
                Issue.record("Expected the last code columns before resize")
            }

            session.send(.key(.home))
            let home = try await recorder.wait(after: resized.sequence, description: "native Home restores indentation and the first code columns") {
                self.hasCodeFocus($0) && self.containsPrefix($0)
            }
            #expect(home.focusedIdentity == themed.focusedIdentity)
            #expect(!home.raster.lines.contains { $0.contains("-LAST") })
            expectAuthoredRows(home)

            session.send(.key(.character("p")))
            let plainHome = try await recorder.wait(after: home.sequence, description: "plain paint retains the first code columns") {
                self.containsPrefix($0) && $0.raster.lines.contains { $0.contains("Paint=plain") }
            }
            #expect(plainHome.focusedIdentity == home.focusedIdentity)
            session.send(.key(.tab))
            let link = try await recorder.wait(after: plainHome.sequence, description: "Tab reaches the report link after the code") { frame in
                frame.focusedIdentity?.description.contains("InlineLink[0]") == true
                    && frame.semantics.focusRegions.contains { region in
                    region.identity == frame.focusedIdentity && region.focusInteractions == .activate
                }
            }
            session.send(.key(.return))
            _ = try await recorder.wait(after: link.sequence, description: "plain modifier preserves the application's link action") {
                $0.raster.lines.contains { $0.contains("Opened=docs") }
            }

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
        frame.raster.lines.contains { $0.hasPrefix("     let FIRST") }
    }

    private func expectAuthoredRows(_ frame: SemanticHostFrame) {
        let lines = frame.raster.lines
        guard let first = lines.firstIndex(where: { $0.hasPrefix("     let FIRST") }),
              let second = lines.firstIndex(where: { $0.hasPrefix("     let SECOND") }) else {
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
    @State private var plain = false
    @State private var opened = false
    private let document = MarkdownDocument(
        "```swift\n    let FIRST = \"0123456789abcdefghijklmnop-LAST\"\n\n    let SECOND = 42\n```\n\n[Docs](docs)"
    )
}

extension MarkdownCodeTestView: View {
    var body: some View {
        let status: String
        if opened {
            status = "Opened=docs"
        } else {
            let paint = plain ? "plain" : "auto"
            status = "Paint=\(paint)"
        }
        return VStack(alignment: .leading, spacing: 0) {
            Text("Theme=\(light ? "light" : "dark")")
            Text(status)
            MarkdownView(document, openLink: OpenLinkAction { destination in
                opened = destination.rawValue == "docs"
                return opened
            })
            .codeHighlighting(plain ? .plain : .automatic)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .chioTheme(light ? .light : .default)
        .onKeyPress { press in
            if press == KeyPress(.character("t"), modifiers: .ctrl) {
                light.toggle()
                return .handled
            }
            if press == KeyPress(.character("p")) {
                plain.toggle()
                return .handled
            }
            return .ignored
        }
    }
}
