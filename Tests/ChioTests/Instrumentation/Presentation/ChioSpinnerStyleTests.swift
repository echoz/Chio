import Chio
import SwiftTUIRuntime
import Testing

@MainActor
struct ChioSpinnerStyleTests {
    @Test("Chio renders the native initial braille frame under both motion policies", arguments: [false, true])
    func nativeInitialFrame(reduceMotion: Bool) {
        let native = DefaultRenderer().render(
            Spinner().spinnerStyle(GlyphSpinnerStyle.automatic)
                .environment(\.accessibilityReduceMotion, reduceMotion),
            proposal: .init(width: 1, height: 1), frameInstant: .zero
        )
        let chio = DefaultRenderer().render(
            Spinner().spinnerStyle(ChioSpinnerStyle())
                .environment(\.accessibilityReduceMotion, reduceMotion),
            proposal: .init(width: 1, height: 1), frameInstant: .zero
        )
        #expect(chio.rasterSurface.lines == native.rasterSurface.lines)
        #expect(chio.rasterSurface.lines == ["⠋"])
    }

    @Test("Spinner stage paint and native progress semantics remain distinct in both themes",
          arguments: [Spinner.Stage.inactive, .active, .finished], [ChioTheme.default, .light])
    func stages(stage: Spinner.Stage, theme: ChioTheme) throws {
        let rendered = DefaultRenderer().render(
            Spinner(stage: stage).spinnerStyle(ChioSpinnerStyle(theme: theme))
                .environment(\.accessibilityReduceMotion, true),
            proposal: .init(width: 1, height: 1), frameInstant: .zero
        )
        let glyph: Character
        let color: Color
        let value: AccessibilityValue?
        switch stage {
        case .inactive: glyph = "·"; color = theme.colors.mutedText; value = .number(0)
        case .active: glyph = "⠋"; color = theme.colors.accent; value = nil
        case .finished: glyph = "✓"; color = theme.colors.success; value = .number(1)
        }
        let cell = try #require(rendered.rasterSurface.cells.flatMap { $0 }.first { $0.character == glyph })
        #expect(cell.style?.foregroundColor == color)
        let progress = try #require(rendered.semanticSnapshot.accessibilityNodes.first { $0.role == .progressBar })
        #expect(progress.control?.value == value)
        #expect(rendered.semanticSnapshot.focusRegions.isEmpty)
    }

    @Test("Reduced-motion rendering stays on the first native frame across frame instants")
    func reducedMotionStaticFrame() {
        let renderer = DefaultRenderer()
        let view = Spinner().spinnerStyle(ChioSpinnerStyle()).environment(\.accessibilityReduceMotion, true)
        let first = renderer.render(view, proposal: .init(width: 1, height: 1), frameInstant: .zero)
        let later = renderer.render(view, proposal: .init(width: 1, height: 1),
                                    frameInstant: MonotonicInstant.zero.advanced(by: .seconds(2)))
        #expect(first.rasterSurface.lines == ["⠋"])
        #expect(later.rasterSurface.cells == first.rasterSurface.cells)
    }

    @Test("Custom theme accents reach native spinner raster cells")
    func customTheme() throws {
        let theme = ChioTheme.default.replacing(colors: ChioTheme.default.colors.replacing(accent: Color(hexRGB: 0x123456)))
        let rendered = DefaultRenderer().render(
            Spinner().spinnerStyle(ChioSpinnerStyle(theme: theme)).environment(\.accessibilityReduceMotion, true),
            proposal: .init(width: 1, height: 1)
        )
        let cell = try #require(rendered.rasterSurface.cells.flatMap { $0 }.first { $0.character == "⠋" })
        #expect(cell.style?.foregroundColor == Color(hexRGB: 0x123456))
    }
}
