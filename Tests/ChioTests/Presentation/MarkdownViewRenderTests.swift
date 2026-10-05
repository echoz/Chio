import Chio
import Foundation
import SwiftTUIRuntime
import Testing

@MainActor
struct MarkdownViewRenderTests {
    @Test("Swift token cells resolve all syntax roles from the current theme",
          arguments: [ChioTheme.default, .light, .btop,
                      ChioTheme.default.replacing(syntax: .init(
                        keyword: .red, type: .blue, string: .green,
                        number: .yellow, comment: .cyan))])
    func syntaxColors(theme: ChioTheme) {
        let source = "```SwIfT additional-info\nlet count: Int = 42\nlet label = \"hello\" // note\n```"
        let surface = DefaultRenderer().render(
            MarkdownView(MarkdownDocument(source)).chioTheme(theme),
            proposal: .init(width: 60, height: 10)
        ).rasterSurface
        expectColor(of: "let", in: surface.cells, color: theme.syntax.keyword)
        expectColor(of: "Int", in: surface.cells, color: theme.syntax.type)
        expectColor(of: "42", in: surface.cells, color: theme.syntax.number)
        expectColor(of: "\"hello\"", in: surface.cells, color: theme.syntax.string)
        expectColor(of: "// note", in: surface.cells, color: theme.syntax.comment)
        expectColor(of: "count", in: surface.cells, color: theme.colors.foreground)
        expectColor(of: ":", in: surface.cells, color: theme.colors.foreground)
        expectColor(of: "=", in: surface.cells, color: theme.colors.foreground)
    }

    @Test("Plain highlighting overrides Swift tokens without changing literal cell geometry",
          arguments: ["\n", "\r\n"])
    func syntaxWhitespace(newline: String) {
        let code = "  let cafe\u{301} = \"你好 👩‍💻\"\t // note  \n\n    let value = 42\n"
        let source = ("```swift\n" + code + "```\n").replacingOccurrences(of: "\n", with: newline)
        let document = MarkdownDocument(source)
        let automatic = DefaultRenderer().render(
            MarkdownView(document).chioTheme(.default),
            proposal: .init(width: 60, height: 12)
        ).rasterSurface
        let plain = DefaultRenderer().render(
            MarkdownView(document).codeHighlighting(.plain).chioTheme(.default),
            proposal: .init(width: 60, height: 12)
        ).rasterSurface
        #expect(automatic.size == plain.size)
        #expect(automatic.lines == plain.lines)
        #expect(automatic.cells.map { $0.map(\.character) } == plain.cells.map { $0.map(\.character) })
        #expect(automatic.cells.map { $0.map(\.spanWidth) } == plain.cells.map { $0.map(\.spanWidth) })
        #expect(automatic.cells.map { $0.map(\.continuationLeadX) } == plain.cells.map { $0.map(\.continuationLeadX) })
        expectColor(of: "let", in: automatic.cells, color: ChioTheme.default.syntax.keyword)
        expectColor(of: "let", in: plain.cells, color: ChioTheme.default.colors.foreground)
        #expect(automatic.cells.flatMap { $0 }.contains { $0.character == "e\u{301}" })
        #expect(automatic.cells.flatMap { $0 }.contains { $0.character == "👩‍💻" && $0.spanWidth == 2 })
        guard let first = automatic.lines.firstIndex(where: { $0.contains("cafe\u{301}") }),
              let last = automatic.lines.firstIndex(where: { $0.contains("value = 42") }) else {
            Issue.record("Expected both literal code lines")
            return
        }
        #expect(last == first + 2)
        #expect(automatic.lines[first + 1].allSatisfy { $0 == " " })
        #expect(last + 1 < automatic.lines.count)
        if last + 1 < automatic.lines.count {
            #expect(automatic.lines[last + 1].allSatisfy { $0 == " " })
        }
        let lf = DefaultRenderer().render(
            MarkdownView(MarkdownDocument("```swift\n" + code + "```\n")).chioTheme(.default),
            proposal: .init(width: 60, height: 12)
        ).rasterSurface
        #expect(automatic.cells == lf.cells)
    }

    @Test("Unknown and absent fence languages retain plain code", arguments: ["", "unknown"])
    func plainLanguage(language: String) {
        let document = MarkdownDocument("```\(language)\nlet value: Int = 42 // note\n```")
        let automatic = DefaultRenderer().render(MarkdownView(document).chioTheme(.default),
                                                  proposal: .init(width: 48, height: 8)).rasterSurface
        let plain = DefaultRenderer().render(MarkdownView(document).codeHighlighting(.plain).chioTheme(.default),
                                              proposal: .init(width: 48, height: 8)).rasterSurface
        #expect(automatic.cells == plain.cells)
        expectColor(of: "let", in: automatic.cells, color: ChioTheme.default.colors.foreground)
    }

    private func expectColor(of text: String, in rows: [[RasterCell]], color: Color) {
        let characters = Array(text)
        for row in rows where row.count >= characters.count {
            for start in 0...(row.count - characters.count) {
                let cells = row[start..<(start + characters.count)]
                if cells.map(\.character) == characters {
                    #expect(cells.allSatisfy { $0.style?.foregroundColor == color }, "Unexpected color for \(text)")
                    return
                }
            }
        }
        Issue.record("Expected visible token \(text)")
    }

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
        theme = theme.replacing(colors: theme.colors.replacing(
            accent: Color(hexRGB: 0x234567),
            heading: Color(hexRGB: 0x123456),
            selectedSurface: Color(hexRGB: 0x456789),
            border: Color(hexRGB: 0x345678)
        ))
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

    @Test("Unlabeled fenced and indented code render without a language header", arguments: [false, true])
    func unlabeledCode(light: Bool) {
        let theme: ChioTheme = light ? .light : .default
        let fenced = DefaultRenderer().render(
            MarkdownView(MarkdownDocument("```\nlet x = 1\n\n  end\n```\n")).chioTheme(theme),
            proposal: .init(width: 24, height: 12)
        ).rasterSurface
        let indented = DefaultRenderer().render(
            MarkdownView(MarkdownDocument("    let x = 1\n\n      end\n")).chioTheme(theme),
            proposal: .init(width: 24, height: 12)
        ).rasterSurface
        #expect(fenced.cells == indented.cells)
        #expect(fenced.lines.first?.trimmingCharacters(in: .whitespaces) == "let x = 1")
        let codeRow = fenced.lines.firstIndex { $0.contains("let x = 1") }
        let lastRow = fenced.lines.firstIndex { $0.contains("end") }
        if let codeRow, let lastRow {
            #expect(lastRow == codeRow + 2)
            #expect(fenced.lines[codeRow + 1].trimmingCharacters(in: .whitespaces).isEmpty)
        } else {
            Issue.record("Expected both unlabeled code lines")
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

    @Test("Empty reference destinations render readable labels without empty parentheses")
    func emptyDestinations() {
        let rendered = DefaultRenderer().render(
            MarkdownView(MarkdownDocument("[Docs]() ![Chart]() ![]()")).chioTheme(.default),
            proposal: .init(width: 40, height: 8)
        )
        let text = rendered.rasterSurface.lines.joined(separator: " ")
        #expect(text.contains("Docs Chart Image"))
        #expect(!text.contains("()"))
        #expect(!rendered.semanticSnapshot.accessibilityNodes.contains { $0.role == .link })
    }
}
