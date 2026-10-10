import Chio
import SwiftTUIRuntime
import Testing

@MainActor
struct ChioTextEntryRenderTests {
    @Test("An empty editor fills its bounded viewport with a stable frame")
    func emptyViewport() {
        let surface = DefaultRenderer().render(
            TextEditor(text: .constant("")).frame(width: 24, height: 8).chioTheme(.default),
            proposal: .init(width: 24, height: 8)
        ).rasterSurface
        #expect(surface.size == CellSize(width: 24, height: 8))
        #expect(surface.lines.first?.contains("╭") == true)
        #expect(surface.lines.last?.contains("╰") == true)
        #expect(surface.lines.dropFirst().dropLast().allSatisfy { $0.hasPrefix("│") && $0.hasSuffix("│") })
    }

    @Test("The native editor honors ambient custom text color inside Chio's frame")
    func customEditorPalette() throws {
        let theme = ChioTheme.default.replacing(colors: ChioTheme.default.colors.replacing(
            foreground: Color(hexRGB: 0xA1B2C3), surface: Color(hexRGB: 0x102030),
            border: Color(hexRGB: 0x456789)
        ))
        let rendered = DefaultRenderer().render(
            TextEditor(text: .constant("Notes\nSecond line"))
                .frame(width: 24, height: 7).chioTheme(theme),
            proposal: .init(width: 24, height: 7)
        )
        let cells = rendered.rasterSurface.cells.flatMap { $0 }
        let first = try #require(cells.first { $0.character == "N" })
        #expect(first.style?.foregroundColor == theme.colors.foreground)
        #expect(first.style?.backgroundColor == theme.colors.surface)
        #expect(cells.contains { $0.character == "╭" && $0.style?.foregroundColor == theme.colors.border })
        #expect(rendered.semanticSnapshot.accessibilityNodes.contains { $0.role == .textEditor })
    }

    @Test("Secure fields conceal synthetic secrets in raster and semantic snapshots",
          arguments: [false, true], [false, true])
    func secureMask(light: Bool, disabled: Bool) {
        let theme: ChioTheme = light ? .light : .default
        let secret = "Synthetic-Secret-482!"
        let rendered = DefaultRenderer().render(
            SecureField("Demo password", text: .constant(secret))
                .disabled(disabled).chioTheme(theme),
            proposal: .init(width: 36, height: 5)
        )
        let display = rendered.rasterSurface.lines.joined(separator: "\n")
        #expect(!display.contains(secret))
        #expect(!String(reflecting: rendered.semanticSnapshot).contains(secret))
        #expect(display.contains("•"))
        #expect(rendered.semanticSnapshot.accessibilityNodes.contains { $0.role == .secureField })
    }

    @Test("Disabled editor text and its Chio frame remain visible in both palettes", arguments: [false, true])
    func disabledEditor(light: Bool) throws {
        let theme: ChioTheme = light ? .light : .default
        let rendered = DefaultRenderer().render(
            TextEditor(text: .constant("Local notes"))
                .disabled(true).frame(width: 24, height: 5).chioTheme(theme),
            proposal: .init(width: 24, height: 5)
        )
        let cells = rendered.rasterSurface.cells.flatMap { $0 }
        let glyph = try #require(cells.first { $0.character == "L" })
        let foreground = try #require(glyph.style?.foregroundColor)
        #expect(foreground != theme.colors.surface)
        #expect(glyph.style?.backgroundColor == theme.colors.surface)
        #expect(rendered.rasterSurface.lines.contains { $0.contains("Local notes") })
        #expect(cells.contains { $0.character == "╭" && $0.style?.foregroundColor == theme.colors.border })
        #expect(rendered.semanticSnapshot.accessibilityNodes.contains { $0.role == .textEditor && !$0.isEnabled })
    }
}
