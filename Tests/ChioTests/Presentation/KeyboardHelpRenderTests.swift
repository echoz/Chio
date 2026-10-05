import Chio
import Foundation
import SwiftTUIRuntime
import Testing

@MainActor
struct KeyboardHelpRenderTests {
    @Test("Grouped help uses each palette's semantic colors", arguments: [ChioTheme.default, .light])
    func palettes(theme: ChioTheme) {
        assertColors(theme)
    }

    @Test("Help and compact hints honor custom colors and descriptor detail placement")
    func customColors() {
        let base = ChioTheme.default
        let theme = base.replacing(colors: base.colors.replacing(
            accent: Color(hexRGB: 0x123456),
            heading: Color(hexRGB: 0x234567),
            secondaryText: Color(hexRGB: 0x345678),
            mutedText: Color(hexRGB: 0x456789),
            surface: Color(hexRGB: 0x56789A)
        ))
        assertColors(theme)
        let hints = DefaultRenderer().render(
            KeyHints([ShortcutHint("k", "Label", detail: "Detail")]).chioTheme(theme),
            proposal: .init(width: 32, height: nil)
        ).rasterSurface
        #expect(hints.lines.map(trim) == ["k Label"])
    }

    @Test("Empty groups are omitted and repeated shortcut descriptions remain visible")
    func groupsAndDuplicates() {
        let shortcut = ShortcutHint("q", "Quit")
        let surface = DefaultRenderer().render(
            KeyboardHelp([
                ShortcutGroup("Hidden", shortcuts: []),
                ShortcutGroup("Actions", shortcuts: [shortcut, shortcut]),
            ]).chioTheme(.default), proposal: .init(width: 32, height: nil)
        ).rasterSurface
        let lines = surface.lines.map(trim)
        #expect(lines.contains("Actions"))
        #expect(!lines.contains("Hidden"))
        #expect(lines.filter { $0 == "q Quit" }.count == 2)
        let hints = DefaultRenderer().render(
            KeyHints([shortcut, shortcut]).chioTheme(.default),
            proposal: .init(width: 32, height: nil)
        ).rasterSurface
        #expect(hints.lines.map(trim) == ["q Quit  q Quit"])
    }

    @Test("Missing shortcuts have an explicit empty state", arguments: [false, true])
    func emptyState(hasEmptyGroup: Bool) {
        let groups = hasEmptyGroup ? [ShortcutGroup("Hidden", shortcuts: [])] : []
        let surface = DefaultRenderer().render(
            KeyboardHelp(groups).chioTheme(.default),
            proposal: .init(width: 32, height: nil)
        ).rasterSurface
        #expect(normalize(surface.lines) == "No keyboard shortcuts available.")
        #expect(surface.size.width <= 32)
    }

    @Test("Long labels, details, headings and wide keys wrap within compact help", arguments: [12, 32])
    func compactWrapping(width: Int) {
        let surface = DefaultRenderer().render(
            KeyboardHelp([ShortcutGroup("Navigation commands", shortcuts: [
                ShortcutHint("界界", "Move through all available results", detail: "Details wrap and finish visibly."),
                ShortcutHint("Ctrl-Shift-Alt-Command-K", "Open commands", detail: ""),
            ])]).chioTheme(.default), proposal: .init(width: width, height: nil)
        ).rasterSurface
        #expect(surface.size.width <= width)
        let words = normalize(surface.lines)
        #expect(words.contains("Navigation"))
        #expect(words.contains("available"))
        #expect(words.contains("results"))
        #expect(words.contains("visibly."))
        #expect(words.contains("Open commands"))
        let compact = surface.lines.joined().filter { !$0.isWhitespace }
        #expect(compact.contains("Ctrl-Shift-Alt-Command-K"))
        let wideCells = surface.cells.flatMap { $0 }.filter { $0.character == "界" && $0.spanWidth == 2 }
        #expect(wideCells.count == 2)
    }

    private func assertColors(_ theme: ChioTheme) {
        let surface = DefaultRenderer().render(
            KeyboardHelp([ShortcutGroup("Group", shortcuts: [ShortcutHint("k", "Label", detail: "Detail")])])
                .chioTheme(theme), proposal: .init(width: 32, height: nil)
        ).rasterSurface
        #expect(surface.lines.map(trim).filter { !$0.isEmpty } == ["Group", "k Label", "Detail"])
        let cells = surface.cells.flatMap { $0 }
        #expect(cells.contains { $0.character == "G" && $0.style?.foregroundColor == theme.colors.heading
            && $0.style?.emphasis.contains(.bold) == true })
        #expect(cells.contains { $0.character == "k" && $0.style?.foregroundColor == theme.colors.accent
            && $0.style?.emphasis.contains(.bold) == true })
        #expect(cells.contains { $0.character == "L" && $0.style?.foregroundColor == theme.colors.secondaryText })
        #expect(cells.contains { $0.character == "D" && $0.style?.foregroundColor == theme.colors.mutedText
            && $0.style?.backgroundColor == theme.colors.surface })
    }

    private func trim(_ line: String) -> String {
        String(line.reversed().drop(while: { $0 == " " }).reversed())
    }

    private func normalize(_ lines: [String]) -> String {
        lines.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
