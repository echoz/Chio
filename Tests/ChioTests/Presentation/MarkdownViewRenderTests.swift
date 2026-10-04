import Chio
import Foundation
import SwiftTUIRuntime
import Testing

@MainActor
struct MarkdownViewRenderTests {
    @Test("Rich paragraphs keep native wrapping and combined cell emphasis", arguments: [12, 28])
    func richParagraph(width: Int) {
        let surface = DefaultRenderer().render(
            MarkdownView(MarkdownDocument("plain ***both*** and **strong** plus *soft*"))
                .chioTheme(.default),
            proposal: .init(width: width, height: 20)
        ).rasterSurface
        #expect(surface.size.width <= width)
        let text = surface.lines.joined(separator: " ")
        #expect(text.contains("plain"))
        #expect(text.contains("both"))
        #expect(text.contains("strong"))
        #expect(text.contains("soft"))
        let cells = surface.cells.flatMap { $0 }
        #expect(cells.contains {
            $0.character == "b" && $0.style?.emphasis.contains(.bold) == true
                && $0.style?.emphasis.contains(.italic) == true
        })
        #expect(cells.contains {
            $0.character == "p" && $0.style?.emphasis.contains(.bold) == false
                && $0.style?.emphasis.contains(.italic) == false
        })
    }

    @Test("Headings, quote markers, and inline code use semantic theme colors",
          arguments: [false, true])
    func theme(light: Bool) {
        var theme = light ? ChioTheme.light : .default
        theme.colors.heading = Color(hexRGB: 0x123456)
        theme.colors.accent = Color(hexRGB: 0x234567)
        theme.colors.border = Color(hexRGB: 0x345678)
        theme.colors.selectedSurface = Color(hexRGB: 0x456789)
        let surface = DefaultRenderer().render(
            MarkdownView(MarkdownDocument("# Heading\n\nA `code` span.\n\n> Quote"))
                .chioTheme(theme),
            proposal: .init(width: 24, height: 12)
        ).rasterSurface
        let cells = surface.cells.flatMap { $0 }
        #expect(cells.contains {
            $0.character == "H" && $0.style?.foregroundColor == theme.colors.heading
                && $0.style?.emphasis.contains(.bold) == true
        })
        #expect(cells.contains {
            $0.character == "c" && $0.style?.foregroundColor == theme.colors.accent
                && $0.style?.backgroundColor == theme.colors.selectedSurface
        })
        #expect(cells.contains {
            $0.character == "│" && $0.style?.foregroundColor == theme.colors.border
        })
        #expect(cells.contains {
            $0.character == "Q" && $0.style?.foregroundColor == theme.colors.secondaryText
        })
    }

    @Test("Narrow Unicode prose wraps by native terminal cells", arguments: [10, 16])
    func unicode(width: Int) {
        let surface = DefaultRenderer().render(
            MarkdownView(MarkdownDocument("你好 **世界** 👩‍💻 café and end"))
                .chioTheme(.default),
            proposal: .init(width: width, height: 20)
        ).rasterSurface
        #expect(surface.size.width <= width)
        let text = surface.lines.joined(separator: " ")
        for word in ["你好", "世界", "👩‍💻", "café", "end"] {
            #expect(text.contains(word))
        }
        #expect(surface.cells.flatMap { $0 }.contains {
            $0.character == "世" && $0.style?.emphasis.contains(.bold) == true
        })
    }

    @Test("Lists wrap under their marker and retain nested content", arguments: [14, 30])
    func nestedLists(width: Int) {
        let surface = DefaultRenderer().render(
            MarkdownView(MarkdownDocument("7. first item wraps here\n   - inner\n8. last"))
                .chioTheme(.default),
            proposal: .init(width: width, height: 20)
        ).rasterSurface
        #expect(surface.size.width <= width)
        let text = surface.lines.joined(separator: " ")
        for word in ["7.", "first", "wraps", "•", "inner", "8.", "last"] {
            #expect(text.contains(word))
        }
        #expect(surface.lines.contains { $0.contains("  • inner") })
    }

    @Test("Code preserves authored columns and blank rows without prose wrapping")
    func codeWhitespace() {
        let surface = DefaultRenderer().render(
            MarkdownView(MarkdownDocument("```swift\n  let x = 1\n\n    end\n```"))
                .chioTheme(.default),
            proposal: .init(width: 24, height: 12)
        ).rasterSurface
        let lines = surface.lines
        #expect(lines.contains { $0.contains("   let x = 1") })
        #expect(lines.contains { $0.contains("     end") })
        let codeRow = lines.firstIndex { $0.contains("let x = 1") }
        let lastRow = lines.firstIndex { $0.contains("end") }
        if let codeRow, let lastRow {
            #expect(lastRow == codeRow + 2)
            #expect(lines[codeRow + 1].trimmingCharacters(in: .whitespaces).isEmpty)
        } else {
            Issue.record("Expected both code lines")
        }
    }

    @Test("Unsupported features remain readable without link activation")
    func fallback() {
        let rendered = DefaultRenderer().render(
            MarkdownView(MarkdownDocument("""
            [Docs](guide.md) ![Chart](plot.png)

            <div>literal</div>
            """)).chioTheme(.default),
            proposal: .init(width: 40, height: 20)
        )
        let text = rendered.rasterSurface.lines.joined(separator: " ")
        for value in ["Docs (guide.md)", "Chart (plot.png)", "<div>literal</div>"] {
            #expect(text.contains(value))
        }
        #expect(!rendered.semanticSnapshot.accessibilityNodes.contains { $0.role == .link })
    }
}
