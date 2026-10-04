import Chio
import SwiftTUIRuntime
import Testing

@MainActor
struct MarkdownTableRenderTests {
    @Test("Markdown tables retain native semantics, visible headers, and rich body cells",
          arguments: [false, true])
    func richCells(light: Bool) {
        let theme = light ? ChioTheme.light : .default
        let rendered = DefaultRenderer().render(
            MarkdownView(MarkdownDocument("""
            | *Name* | `State` |
            | --- | --- |
            | **Agent** | `done` |
            | plain | ready |
            """)).chioTheme(theme),
            proposal: .init(width: 40, height: 20)
        )
        let surface = rendered.rasterSurface
        let text = surface.lines.joined(separator: "\n")
        for value in ["Name", "State", "Agent", "done", "plain", "ready"] {
            #expect(text.contains(value))
        }
        #expect(!text.contains("*Name*"))
        #expect(!text.contains("`State`"))
        #expect(rendered.semanticSnapshot.accessibilityNodes.contains { $0.role == .table })
        let cells = surface.cells.flatMap { $0 }
        #expect(cells.contains {
            $0.character == "N" && $0.style?.foregroundColor == theme.colors.heading
                && $0.style?.backgroundColor == theme.colors.selectedSurface
                && $0.style?.emphasis.contains(.italic) == false
        })
        #expect(cells.contains {
            $0.character == "S" && $0.style?.foregroundColor == theme.colors.heading
                && $0.style?.backgroundColor == theme.colors.selectedSurface
        })
        #expect(cells.contains {
            $0.character == "A" && $0.style?.emphasis.contains(.bold) == true
                && $0.style?.foregroundColor == theme.colors.foreground
                && $0.style?.backgroundColor == theme.colors.surface
        })
        #expect(cells.contains {
            $0.character == "d" && $0.style?.foregroundColor == theme.colors.accent
                && $0.style?.backgroundColor == theme.colors.selectedSurface
        })
    }

    @Test("Column alignment uses cell widths and preserves empty Unicode cells")
    func columnAlignment() throws {
        let surface = DefaultRenderer().render(
            MarkdownView(MarkdownDocument("""
            | One | Two | Three |
            | :--- | :---: | ---: |
            | L | C | R |
            | xxxxxxxx | yyyyyyy | zzzzzzzzz |
            | 你好 | | Z |
            """)).chioTheme(.default),
            proposal: .init(width: 60, height: 20)
        ).rasterSurface
        let row = try #require(surface.cells.first { cells in
            cells.contains { $0.character == "L" }
                && cells.contains { $0.character == "C" }
                && cells.contains { $0.character == "R" }
        })
        let joins = row.indices.filter { row[$0].character == "│" }
        try #require(joins.count == 4)
        let left = try #require(row.firstIndex { $0.character == "L" })
        let center = try #require(row.firstIndex { $0.character == "C" })
        let right = try #require(row.firstIndex { $0.character == "R" })
        #expect(left - joins[0] == 2)
        #expect(abs((center - joins[1]) - (joins[2] - center)) <= 1)
        #expect(joins[3] - right == 2)

        let unicode = try #require(surface.cells.first { cells in
            cells.contains { $0.character == "你" }
        })
        #expect(surface.lines.contains { $0.contains("你好") })
        #expect(unicode.indices.filter { unicode[$0].character == "│" } == joins)
        #expect(unicode.firstIndex { $0.character == "Z" } == right)
        #expect(unicode[(joins[1] + 1)..<joins[2]].allSatisfy { $0.character == " " })
    }

    @Test("Wide tables clip horizontally without collapsing rows or following prose",
          arguments: [12, 24])
    func narrowViewport(width: Int) throws {
        let rendered = DefaultRenderer().render(
            MarkdownView(MarkdownDocument("""
            Before

            | Row | Deliberately wide heading beyond viewport |
            | --- | --- |
            | first | long value ending in hidden-tail |
            | second | another long value |
            | third | final long value |

            After
            """)).chioTheme(.default),
            proposal: .init(width: width, height: 24)
        )
        let surface = rendered.rasterSurface
        #expect(surface.size.width <= width)
        let lines = surface.lines
        for value in ["Before", "Row", "first", "second", "third", "After"] {
            #expect(lines.contains { $0.contains(value) })
        }
        #expect(!lines.joined(separator: "\n").contains("hidden-tail"))
        let first = try #require(lines.firstIndex { $0.contains("first") })
        let second = try #require(lines.firstIndex { $0.contains("second") })
        let third = try #require(lines.firstIndex { $0.contains("third") })
        let after = try #require(lines.firstIndex { $0.contains("After") })
        #expect(first < second && second < third && third < after)
        #expect(rendered.semanticSnapshot.accessibilityNodes.contains { $0.role == .table })
    }

    @Test("Header-only Markdown and native tables share customized header colors and native borders",
          arguments: [false, true])
    func nativeAndHeaderOnlyTheme(light: Bool) {
        var theme = light ? ChioTheme.light : .default
        theme.colors.heading = Color(hexRGB: 0x123456)
        theme.colors.border = Color(hexRGB: 0x345678)
        theme.colors.selectedSurface = Color(hexRGB: 0x456789)
        let markdown = DefaultRenderer().render(
            MarkdownView(MarkdownDocument("| Header |\n| --- |"))
                .chioTheme(theme),
            proposal: .init(width: 24, height: 12)
        )
        let native = DefaultRenderer().render(
            Table(columns: [TableColumn("Header")]) {
                TableRow { Text("value") }
            }.chioTheme(theme),
            proposal: .init(width: 24, height: 12)
        )
        for rendered in [markdown, native] {
            #expect(rendered.rasterSurface.lines.contains { $0.contains("Header") })
            #expect(rendered.semanticSnapshot.accessibilityNodes.contains { $0.role == .table })
            let cells = rendered.rasterSurface.cells.flatMap { $0 }
            #expect(cells.contains {
                $0.character == "H" && $0.style?.foregroundColor == theme.colors.heading
                    && $0.style?.backgroundColor == theme.colors.selectedSurface
            })
            // Upstream's default control chrome masks TableStylePresentation.borderStyle.
            // Verify native rounded geometry; authored border color remains an upstream gap.
            #expect(cells.contains { $0.character == "╭" })
            #expect(cells.contains { $0.character == "╰" })
        }
        #expect(native.rasterSurface.lines.contains { $0.contains("value") })
    }
}
