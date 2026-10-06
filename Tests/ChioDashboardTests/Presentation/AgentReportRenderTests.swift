@testable import ChioDashboard
import Chio
import SwiftTUIRuntime
import Testing

@MainActor
struct AgentReportRenderTests {
    @Test("Reports retain their header, complete navigation hints, and captured agent across sizes and themes",
          arguments: [CellSize(width: 100, height: 30), CellSize(width: 50, height: 30),
                      CellSize(width: 36, height: 18)], ExampleTheme.allCases)
    func layout(size: CellSize, appearance: ExampleTheme) {
        let view = AgentReportView(report: AgentReport(agent: Agent.examples[3]),
                                   themeChoice: .constant(appearance), close: {})
        let surface = DefaultRenderer().render(
            view, proposal: .init(width: size.width, height: size.height), frameInstant: .zero
        ).rasterSurface
        let text = surface.lines.joined(separator: "\n")
        #expect(surface.size == size)
        #expect(text.contains("/ agent report"))
        #expect(text.contains("snapshot"))
        #expect(text.contains("Docs Agent"))
        #expect(text.contains("Complete"))
        #expect(text.contains("↑↓ scroll"))
        #expect(text.contains("home/end jump"))
        #expect(text.contains("esc back"))
        #expect(text.contains("^T theme"))
        let theme = appearance.theme
        #expect(surface.cells.flatMap { $0 }.contains {
            $0.character == "c" && $0.style?.foregroundColor == theme.colors.accent
        })
    }

    @Test("User-authored report names and summaries render Markdown punctuation literally")
    func literalMetadata() {
        let name = "**Build** [docs](target)"
        let summary = "`swift` _test_ <tag> \\path"
        let agent = Agent(id: "literal", name: name, summary: summary, phase: .idle)
        let surface = DefaultRenderer().render(
            MarkdownView(AgentReport(agent: agent).document).chioTheme(.default),
            proposal: .init(width: 100, height: nil)
        ).rasterSurface
        let text = surface.lines.joined(separator: "\n")
        #expect(text.contains(name))
        #expect(text.contains(summary))
        #expect(!text.contains("docs (target)"))
    }
}
