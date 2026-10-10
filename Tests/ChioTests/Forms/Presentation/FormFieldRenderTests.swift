import Chio
import Foundation
import SwiftTUIRuntime
import Testing

@MainActor
struct FormFieldRenderTests {
    @Test("Default and explicit empty descriptions omit helper rows and semantic text")
    func emptyDescription() {
        let omitted = DefaultRenderer().render(
            FormField("Name") { Text("Value") }.chioTheme(.default),
            proposal: .init(width: 24, height: nil)
        )
        let empty = DefaultRenderer().render(
            FormField("Name", description: "") { Text("Value") }.chioTheme(.default),
            proposal: .init(width: 24, height: nil)
        )
        #expect(omitted.rasterSurface.size.height == 2)
        #expect(empty.rasterSurface == omitted.rasterSurface)
        #expect(omitted.semanticSnapshot.accessibilityNodes.compactMap(\.label) == ["Name", "Value"])
        #expect(empty.semanticSnapshot.accessibilityNodes.compactMap(\.label) == ["Name", "Value"])
    }

    @Test("A present empty error still replaces the helper and shows the error marker")
    func emptyError() {
        let rendered = DefaultRenderer().render(
            FormField("Name", description: "Hidden helper", error: "") { Text("Value") }
                .chioTheme(.default), proposal: .init(width: 24, height: nil)
        )
        #expect(rendered.rasterSurface.size.height == 3)
        #expect(rendered.rasterSurface.lines.contains { $0.contains("Error:") })
        #expect(!rendered.rasterSurface.lines.contains { $0.contains("Hidden helper") })
        let labels = rendered.semanticSnapshot.accessibilityNodes.compactMap(\.label)
        #expect(labels.contains("Error: "))
        #expect(!labels.contains("Hidden helper"))
        #expect(rendered.rasterSurface.cells.flatMap { $0 }.contains {
            $0.character == "E" && $0.style?.foregroundColor == ChioTheme.default.colors.error
        })
    }

    @Test("Headings and helpers wrap within narrow field widths", arguments: [12, 24])
    func helperTheme(width: Int) {
        var theme = ChioTheme.default
        theme = theme.replacing(colors: theme.colors.replacing(
            heading: Color(hexRGB: 0x123456),
            secondaryText: Color(hexRGB: 0x654321)
        ))
        let surface = DefaultRenderer().render(
            FormField("Agent name", description: "Helpful words wrap here") {
                Text("Value")
            }.chioTheme(theme),
            proposal: .init(width: width, height: 10)
        ).rasterSurface
        #expect(surface.size.width <= width)
        let text = surface.lines.joined(separator: " ")
        #expect(text.contains("Agent name"))
        #expect(text.contains("Helpful"))
        #expect(text.contains("here"))
        let cells = surface.cells.flatMap { $0 }
        #expect(cells.contains { $0.character == "A" && $0.style?.foregroundColor == theme.colors.heading })
        #expect(cells.contains { $0.character == "H" && $0.style?.foregroundColor == theme.colors.secondaryText })
    }

    @Test("Clearly marked errors replace helpers and use the current error palette",
          arguments: [12, 24])
    func errorTheme(width: Int) {
        var theme = ChioTheme.default
        theme = theme.replacing(colors: theme.colors.replacing(error: Color(hexRGB: 0xA12345)))
        let surface = DefaultRenderer().render(
            FormField("Name", description: "Hidden helper", error: "Required name") {
                Text("Value")
            }.chioTheme(theme),
            proposal: .init(width: width, height: 10)
        ).rasterSurface
        #expect(surface.size.width <= width)
        let text = surface.lines.joined(separator: " ")
        #expect(text.contains("Error:"))
        #expect(text.contains("Required"))
        #expect(text.contains("name"))
        #expect(!text.contains("Hidden"))
        #expect(surface.cells.flatMap { $0 }.contains {
            $0.character == "E" && $0.style?.foregroundColor == theme.colors.error
        })
    }

    @Test("Form fields show one heading while retaining native control semantics")
    func nativeLabels() {
        let rendered = DefaultRenderer().render(
            VStack(alignment: .leading, spacing: 1) {
                FormField("Model") {
                    Picker("Model", selection: .constant("small")) {
                        Text("Small").tag("small")
                        Text("Large").tag("large")
                    }
                }
                FormField("Confirm") { Toggle("Confirm", isOn: .constant(true)) }
            }.chioTheme(.default),
            proposal: .init(width: 24, height: 10)
        )
        let text = rendered.rasterSurface.lines.joined(separator: "\n")
        #expect(text.components(separatedBy: "Model").count == 2)
        #expect(text.components(separatedBy: "Confirm").count == 2)
        #expect(text.contains("Small"))
        #expect(text.contains("On"))
        #expect(rendered.semanticSnapshot.accessibilityNodes.contains { $0.role == .picker })
        #expect(rendered.semanticSnapshot.accessibilityNodes.contains { $0.role == .toggle })
    }

    @Test("Themed picker and toggle content stays compact and uses semantic colors")
    func nativeTheme() {
        var theme = ChioTheme.default
        theme = theme.replacing(colors: theme.colors.replacing(
            foreground: Color(hexRGB: 0x123456),
            mutedText: Color(hexRGB: 0x345678),
            surface: Color(hexRGB: 0x456789),
            success: Color(hexRGB: 0x234567)
        ))
        let picker = DefaultRenderer().render(
            Picker("Model", selection: .constant("s")) {
                Text("Small").tag("s")
                Text("Large").tag("l")
            }.chioTheme(theme), proposal: .init(width: 24, height: 1)
        ).rasterSurface
        #expect(picker.size.height == 1)
        #expect(picker.cells.flatMap { $0 }.contains {
            $0.character == "S" && $0.style?.foregroundColor == theme.colors.foreground
                && $0.style?.backgroundColor == theme.colors.surface
        })
        let toggle = DefaultRenderer().render(
            Toggle("Confirm", isOn: .constant(true)).chioTheme(theme),
            proposal: .init(width: 24, height: 1)
        ).rasterSurface
        #expect(toggle.size.height == 1)
        #expect(toggle.cells.flatMap { $0 }.contains {
            $0.character == "✓" && $0.style?.foregroundColor == theme.colors.success
        })
        #expect(toggle.cells.flatMap { $0 }.contains {
            $0.character == "O" && $0.style?.foregroundColor == theme.colors.foreground
        })
    }

    @Test("Disabled native controls remain visible and dimmed")
    func disabledControls() throws {
        let theme = ChioTheme.default
        let surface = DefaultRenderer().render(
            VStack(alignment: .leading, spacing: 0) {
                Picker("Model", selection: .constant("s")) { Text("Small").tag("s") }
                Toggle("Confirm", isOn: .constant(false))
            }.disabled(true).chioTheme(theme),
            proposal: .init(width: 24, height: 2)
        ).rasterSurface
        #expect(surface.lines.contains { $0.contains("Small") })
        #expect(surface.lines.contains { $0.contains("Off") })
        // The public raster bakes 60% text opacity into its foreground color
        // against the surface, then resets cell opacity to avoid double dimming.
        let dimmedForeground = theme.colors.foreground.mixed(with: theme.colors.surface, amount: 0.4)
        for character in [Character("S"), Character("O")] {
            let cell = surface.cells.flatMap { $0 }.first { $0.character == character }
            let foreground = try #require(cell?.style?.foregroundColor)
            // Raster storage rounds color components; compare the blend within
            // floating-point precision rather than requiring bit identity.
            #expect(abs(foreground.red - dimmedForeground.red) < 0.000001)
            #expect(abs(foreground.green - dimmedForeground.green) < 0.000001)
            #expect(abs(foreground.blue - dimmedForeground.blue) < 0.000001)
            #expect(cell?.style?.opacity == 1)
        }
    }
}
