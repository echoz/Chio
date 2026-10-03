import Chio
import SwiftTUIRuntime
import Testing

@MainActor
struct KeyHintsRenderTests {
    @Test("Key hints wrap whole shortcuts into readable rows", arguments: [10, 16, 20, 40])
    func wholeHintWrapping(width: Int) {
        let surface = DefaultRenderer().render(
            KeyHints {
                KeyHint("↑↓", "move")
                KeyHint("/", "search")
                KeyHint("↵", "run")
                KeyHint("esc", "clear")
            }.chioTheme(.default),
            proposal: .init(width: width, height: nil)
        ).rasterSurface

        let expected: [String]
        switch width {
        case 10: expected = ["↑↓ move", "/ search", "↵ run", "esc clear"]
        case 16: expected = ["↑↓ move", "/ search  ↵ run", "esc clear"]
        case 20: expected = ["↑↓ move  / search", "↵ run  esc clear"]
        default: expected = ["↑↓ move  / search  ↵ run  esc clear"]
        }
        #expect(surface.lines.map(trimTrailingSpaces) == expected)
        #expect(surface.size.width <= width)
    }

    @Test("Wrapping measures wide glyphs in terminal cells", arguments: [14, 15])
    func wideGlyphWrapping(width: Int) {
        let surface = DefaultRenderer().render(
            KeyHints {
                KeyHint("界", "広い")
                KeyHint("q", "quit")
            }.chioTheme(.default),
            proposal: .init(width: width, height: nil)
        ).rasterSurface

        #expect(surface.lines.map(trimTrailingSpaces) == (width == 14
            ? ["界 広い", "q quit"] : ["界 広い  q quit"]))
        #expect(surface.cells.flatMap { $0 }.contains { $0.character == "界" && $0.spanWidth == 2 })
        #expect(surface.size.width <= width)
    }

    @Test("Hints use customized accent, secondary text, and spacing")
    func hintTheme() {
        var theme = ChioTheme.default
        theme.colors.accent = Color(hexRGB: 0x102030)
        theme.colors.secondaryText = Color(hexRGB: 0x405060)
        theme.spacing = .init(hintGap: 3)
        let surface = DefaultRenderer().render(
            KeyHints {
                KeyHint("q", "quit")
                KeyHint("/", "search")
            }.chioTheme(theme),
            proposal: .init(width: 32, height: nil)
        ).rasterSurface

        #expect(surface.lines.map(trimTrailingSpaces) == ["q quit   / search"])
        let cells = surface.cells.flatMap { $0 }
        #expect(cells.contains {
            $0.character == "/" && $0.style?.foregroundColor == theme.colors.accent
                && $0.style?.emphasis.contains(.bold) == true
        })
        #expect(cells.contains { $0.character == "s" && $0.style?.foregroundColor == theme.colors.secondaryText })
    }

    @Test("Status footer retains its separator and wrapped hints at narrow widths")
    func statusBarWrapping() {
        var theme = ChioTheme.default
        theme.colors.border = Color(hexRGB: 0x234567)
        let surface = DefaultRenderer().render(
            StatusBar {
                KeyHints {
                    KeyHint("/", "search")
                    KeyHint("esc", "clear")
                }
            }.chioTheme(theme),
            proposal: .init(width: 16, height: nil)
        ).rasterSurface

        #expect(surface.lines.map(trimTrailingSpaces) == [
            "────────────────", "", "/ search", "esc clear",
        ])
        #expect(surface.cells[0].allSatisfy { $0.style?.foregroundColor == theme.colors.border })
    }
}

private func trimTrailingSpaces(_ line: String) -> String {
    String(line.reversed().drop(while: { $0 == " " }).reversed())
}
