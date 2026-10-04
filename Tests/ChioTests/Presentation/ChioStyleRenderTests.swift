import Chio
import SwiftTUIRuntime
import Testing

@MainActor
struct ChioStyleRenderTests {
    @Test("Determinate progress has stable terminal cells and semantic completion colors",
          arguments: [0.0, 0.5, 1.0])
    func progressCells(value: Double) {
        let surface = DefaultRenderer().render(
            ProgressView(value: value, barWidth: 8) { EmptyView() } currentValueLabel: { EmptyView() }
                .chioTheme(.default),
            proposal: .init(width: 8, height: 1)
        ).rasterSurface

        let expected: String
        switch value {
        case 0: expected = "────────"
        case 0.5: expected = "━━━━────"
        default: expected = "━━━━━━━━"
        }
        #expect(surface.lines == [expected])
        let cells = surface.cells.flatMap { $0 }
        #expect(cells.filter { $0.character == "─" }.allSatisfy {
            $0.style?.foregroundColor == ChioTheme.default.colors.border
        })
        #expect(cells.filter { $0.character == "━" }.allSatisfy {
            $0.style?.foregroundColor == (value == 1
                ? ChioTheme.default.colors.success : ChioTheme.default.colors.accent)
        })
    }

    @Test("Custom progress treatments and palette reach native controls")
    func customProgressTheme() {
        var theme = ChioTheme.default
        theme.colors.accent = Color(hexRGB: 0x123456)
        theme.colors.border = Color(hexRGB: 0x654321)
        theme.colors.surface = Color(hexRGB: 0x181818)
        theme.treatments.progressFilledGlyph = "#"
        theme.treatments.progressEmptyGlyph = "."
        let surface = DefaultRenderer().render(
            ProgressView(value: 0.5, barWidth: 8) { EmptyView() } currentValueLabel: { EmptyView() }
                .chioTheme(theme),
            proposal: .init(width: 8, height: 1)
        ).rasterSurface

        #expect(surface.lines == ["####...."])
        #expect(surface.cells[0][0].style?.foregroundColor == theme.colors.accent)
        #expect(surface.cells[0][4].style?.foregroundColor == theme.colors.border)
        #expect(surface.cells[0][0].style?.backgroundColor == theme.colors.surface)
    }

    @Test("Indeterminate progress stays visible with motion disabled")
    func motionDisabledProgress() {
        let view = ProgressView(barWidth: 8)
            .chioTheme(.default)
            .environment(\.accessibilityReduceMotion, true)
        let first = DefaultRenderer().render(view, proposal: .init(width: 8, height: 1))
        let second = DefaultRenderer().render(view, proposal: .init(width: 8, height: 1))
        let cells = first.rasterSurface.cells.flatMap { $0 }

        #expect(first.rasterSurface.lines == second.rasterSurface.lines)
        #expect(cells.filter { $0.character == "━" || $0.character == "─" }.count == 8)
        #expect(cells.contains { $0.character == "━" && $0.style?.foregroundColor == ChioTheme.default.colors.accent })
        #expect(first.semanticSnapshot.accessibilityNodes.contains { $0.role == .progressBar })
    }

    @Test("Group headings, text, and borders use customized semantic colors at narrow widths",
          arguments: [16, 32])
    func groupBoxTheme(width: Int) {
        var theme = ChioTheme.default
        theme.colors.heading = Color(hexRGB: 0x112233)
        theme.colors.foreground = Color(hexRGB: 0x223344)
        theme.colors.border = Color(hexRGB: 0x334455)
        theme.colors.surface = Color(hexRGB: 0x445566)
        let surface = DefaultRenderer().render(
            GroupBox("Agents") { Text("Ready") }.chioTheme(theme),
            proposal: .init(width: width, height: 7)
        ).rasterSurface

        #expect(surface.lines.contains { $0.contains("Agents") })
        #expect(surface.lines.contains { $0.contains("Ready") })
        #expect(surface.size.width <= width)
        let cells = surface.cells.flatMap { $0 }
        #expect(cells.contains { $0.character == "A" && $0.style?.foregroundColor == theme.colors.heading })
        #expect(cells.contains { $0.character == "R" && $0.style?.foregroundColor == theme.colors.foreground })
        #expect(cells.contains { $0.character == "╭" && $0.style?.foregroundColor == theme.colors.border })
        #expect(cells.contains { $0.character == "R" && $0.style?.backgroundColor == theme.colors.surface })
    }

    @Test("Native text fields retain readable prompt and value colors in a narrow theme",
          arguments: ["", "query"])
    func textFieldTheme(value: String) {
        var theme = ChioTheme.default
        theme.colors.foreground = Color(hexRGB: 0x235679)
        theme.colors.mutedText = Color(hexRGB: 0xAB7890)
        theme.colors.border = Color(hexRGB: 0x456789)
        let surface = DefaultRenderer().render(
            TextField("Search…", text: .constant(value)).chioTheme(theme),
            proposal: .init(width: 16, height: 3)
        ).rasterSurface

        #expect(surface.lines.contains { $0.contains(value.isEmpty ? "Search…" : value) })
        let cells = surface.cells.flatMap { $0 }
        let firstCharacter: Character = value.isEmpty ? "S" : "q"
        let expectedColor = value.isEmpty ? theme.colors.mutedText : theme.colors.foreground
        #expect(cells.contains { $0.character == firstCharacter && $0.style?.foregroundColor == expectedColor })
        #expect(cells.contains { $0.character == "╭" && $0.style?.foregroundColor == theme.colors.border })
        #expect(surface.size.width <= 16)
    }

    @Test("Search selection is visibly distinct and inherits custom marker and colors")
    func searchSelectionTheme() {
        var theme = ChioTheme.default
        theme.colors.accent = Color(hexRGB: 0x13579B)
        theme.colors.selectedSurface = Color(hexRGB: 0x2468AC)
        theme.colors.foreground = Color(hexRGB: 0x987654)
        theme.treatments.selectionMarker = ">"
        let surface = DefaultRenderer().render(
            SearchableList(RenderItem.fixtures, selection: .constant("b"), searchText: \.name) {
                Text($0.name)
            }
            .chioTheme(theme),
            proposal: .init(width: 32, height: 10)
        ).rasterSurface

        #expect(surface.lines.contains { $0.contains("> Beta") })
        #expect(surface.lines.contains { $0.contains("Alpha") })
        #expect(surface.lines.contains { $0.contains("Search…") })
        #expect(surface.lines.contains { $0.contains("2 of 2 items") })
        let cells = surface.cells.flatMap { $0 }
        #expect(cells.contains { $0.character == ">" && $0.style?.foregroundColor == theme.colors.accent })
        #expect(cells.contains { $0.character == "B" && $0.style?.backgroundColor == theme.colors.selectedSurface })
    }

    @Test("Empty source and unmatched search have distinct messages and retain a search field")
    func emptyStates() {
        let empty = DefaultRenderer().render(
            SearchableList([RenderItem](), selection: .constant(nil), searchText: \.name) {
                Text($0.name)
            }.chioTheme(.default),
            proposal: .init(width: 60, height: 8)
        ).rasterSurface.lines.joined(separator: "\n")
        let unmatched = DefaultRenderer().render(
            SearchableList(RenderItem.fixtures, selection: .constant(nil), query: .constant("zzz"),
                           searchText: \.name) { Text($0.name) }.chioTheme(.default),
            proposal: .init(width: 60, height: 8)
        ).rasterSurface.lines.joined(separator: "\n")

        #expect(empty.contains("Search…"))
        #expect(empty.contains("No items yet."))
        #expect(!empty.contains("No matches."))
        #expect(unmatched.contains("zzz"))
        #expect(unmatched.contains("No matches. Clear the search to see all items."))
        #expect(!unmatched.contains("No items yet."))
    }
}

private struct RenderItem {
    let id: String
    let name: String

    static let fixtures = [
        RenderItem(id: "a", name: "Alpha"),
        RenderItem(id: "b", name: "Beta"),
    ]
}

extension RenderItem: Identifiable {}
