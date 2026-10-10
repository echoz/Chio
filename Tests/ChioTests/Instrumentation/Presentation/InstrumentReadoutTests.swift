import Chio
import SwiftTUIRuntime
import Testing

@MainActor
struct InstrumentReadoutTests {
    private func render(_ value: String, style: InstrumentReadout.Style = .segmented,
                        width: Int? = nil, height: Int? = nil) -> RenderSnapshot {
        DefaultRenderer().render(InstrumentReadout(value, style: style),
                                 proposal: ProposedSize(width: width, height: height))
    }

    @Test("Segmented digits retain their complete three-row lettering")
    func digits() {
        let fixtures: [(String, [String])] = [
            ("0", [" _ ", "| |", "|_|"]), ("1", ["   ", "  |", "  |"]),
            ("2", [" _ ", " _|", "|_ "]), ("3", [" _ ", " _|", " _|"]),
            ("4", ["   ", "|_|", "  |"]), ("5", [" _ ", "|_ ", " _|"]),
            ("6", [" _ ", "|_ ", "|_|"]), ("7", [" _ ", "  |", "  |"]),
            ("8", [" _ ", "|_|", "|_|"]), ("9", [" _ ", "|_|", " _|"]),
        ]
        for (value, rows) in fixtures {
            let surface = render(value).rasterSurface
            #expect(surface.lines == rows)
            #expect(surface.size == CellSize(width: 3, height: 3))
        }
    }

    @Test("Signs, decimal points and colons compose without reformatting values")
    func punctuation() {
        let fixtures: [(String, [String])] = [
            ("-", ["   ", " _ ", "   "]), ("+", ["   ", "_|_", " | "]),
            (".", [" ", " ", "."]), (":", [" ", ".", "."]),
            ("-1.2", ["           _ ", " _    |    _|", "      | . |_ "]),
            ("1:02", ["       _   _ ", "  | . | |  _|", "  | . |_| |_ "]),
        ]
        for (value, rows) in fixtures {
            #expect(render(value).rasterSurface.lines == rows)
            #expect(render(value).semanticSnapshot.accessibilityNodes.compactMap(\.label) == [value])
        }
    }

    @Test("Complete lettering fits only when both native allocation dimensions permit it")
    func allocations() {
        let expected = render("12").rasterSurface
        #expect(expected.lines == ["     _ ", "  |  _|", "  | |_ "])
        for width in [7, 8, 20] {
            for height in [3, 4, 8] {
                // The renderer's canvas retains the proposed size; compare the
                // complete lettering inside that allocation, including padding.
                let native = DefaultRenderer().render(
                    Text(verbatim: "     _ \n  |  _|\n  | |_ ").fixedSize()
                        .foregroundStyle(ChioTheme.default.colors.accent),
                    proposal: ProposedSize(width: width, height: height))
                #expect(render("12", width: width, height: height).rasterSurface == native.rasterSurface)
            }
        }
        for width in [0, 1, 2, 6, 7, 20] {
            for height in [0, 1, 2, 3, 4] {
                let isTooNarrow = width < 7
                let isTooShort = height < 3
                guard isTooNarrow || isTooShort else { continue }
                let result = render("12", width: width, height: height)
                let native = DefaultRenderer().render(
                    Text(verbatim: "12").foregroundStyle(ChioTheme.default.colors.accent)
                        .accessibilityLabel("12"),
                    proposal: ProposedSize(width: width, height: height))
                #expect(result.rasterSurface == native.rasterSurface)
                #expect(result.semanticSnapshot.accessibilityNodes.compactMap(\.label)
                        == native.semanticSnapshot.accessibilityNodes.compactMap(\.label))
            }
        }
    }

    @Test("An inherited line limit preserves complete lettering or chooses ordinary text")
    func inheritedLineLimit() {
        for lineLimit in [1, 2] {
            for height in [1, 2, 3] {
                let proposal = ProposedSize(width: 7, height: height)
                let result = DefaultRenderer().render(
                    InstrumentReadout("12").lineLimit(lineLimit), proposal: proposal)
                let expected: RenderSnapshot
                if height >= 3 {
                    expected = DefaultRenderer().render(
                        Text(verbatim: "     _ \n  |  _|\n  | |_ ").fixedSize()
                            .foregroundStyle(ChioTheme.default.colors.accent),
                        proposal: proposal)
                } else {
                    expected = DefaultRenderer().render(
                        Text(verbatim: "12").lineLimit(lineLimit)
                            .foregroundStyle(ChioTheme.default.colors.accent),
                        proposal: proposal)
                }
                #expect(result.rasterSurface == expected.rasterSurface)
                #expect(result.semanticSnapshot.accessibilityNodes.compactMap(\.label) == ["12"])
            }
        }
    }

    @Test("Unsupported, empty and overlong values use ordinary native text")
    func unsupportedValues() {
        let values = ["", " ", "42 bpm", "NaN", "1/2", "１２", "−12", "1\n2",
                      String(repeating: "8", count: 33), String(repeating: "8", count: 1_000)]
        for value in values {
            for width in [nil, 0, 1, 8, 40] as [Int?] {
                let result = render(value, width: width, height: 3)
                let native = DefaultRenderer().render(
                    Text(verbatim: value).foregroundStyle(ChioTheme.default.colors.accent)
                        .accessibilityLabel(value),
                    proposal: ProposedSize(width: width, height: 3))
                #expect(result.rasterSurface == native.rasterSurface)
                #expect(result.semanticSnapshot.accessibilityNodes.compactMap(\.label)
                        == native.semanticSnapshot.accessibilityNodes.compactMap(\.label))
            }
        }
        #expect(render(String(repeating: "8", count: 32)).rasterSurface.size
                == CellSize(width: 127, height: 3))
    }

    @Test("Plain style preserves the supplied text and uses native wrapping")
    func plain() {
        for value in ["12.5", "0:00", "42 bpm"] {
            for width in [nil, 1, 4, 32] as [Int?] {
                let result = render(value, style: .plain, width: width, height: 4)
                let native = DefaultRenderer().render(
                    Text(verbatim: value).foregroundStyle(ChioTheme.default.colors.accent)
                        .accessibilityLabel(value),
                    proposal: ProposedSize(width: width, height: 4))
                #expect(result.rasterSurface == native.rasterSurface)
            }
        }
    }

    @Test("Both styles use theme accent and publish one passive value with caller overrides")
    func semanticsAndTheme() {
        let custom = ChioTheme.default.replacing(
            colors: ChioTheme.default.colors.replacing(accent: Color(hexRGB: 0x123456)))
        for theme in [ChioTheme.default, .light, .btop, custom] {
            for style in [InstrumentReadout.Style.plain, .segmented] {
                for size in [CellSize(width: 32, height: 3), CellSize(width: 5, height: 1)] {
                    let result = DefaultRenderer().render(
                        InstrumentReadout("-12.5", style: style).chioTheme(theme),
                        proposal: ProposedSize(width: size.width, height: size.height))
                    #expect(result.semanticSnapshot.accessibilityNodes.compactMap(\.label) == ["-12.5"])
                    #expect(result.semanticSnapshot.focusRegions.isEmpty)
                    let painted = result.rasterSurface.cells.flatMap { $0 }.filter { $0.character != " " }
                    #expect(!painted.isEmpty)
                    #expect(painted.allSatisfy { $0.style?.foregroundColor == theme.colors.accent })
                    let labeled = DefaultRenderer().render(
                        InstrumentReadout("-12.5", style: style)
                            .accessibilityLabel("Temperature: minus 12.5 degrees").chioTheme(theme),
                        proposal: ProposedSize(width: size.width, height: size.height))
                    #expect(labeled.semanticSnapshot.accessibilityNodes.compactMap(\.label)
                            == ["Temperature: minus 12.5 degrees"])
                }
            }
        }
    }
}
