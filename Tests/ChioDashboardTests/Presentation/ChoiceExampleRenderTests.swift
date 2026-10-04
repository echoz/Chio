@testable import ChioDashboard
import Chio
import SwiftTUIRuntime
import Testing

@MainActor
struct ChoiceExampleRenderTests {
    @Test("Single-choice chrome and actions remain visible across sizes and themes",
          arguments: [CellSize(width: 100, height: 30), CellSize(width: 50, height: 30),
                      CellSize(width: 36, height: 18)], [false, true])
    func languageLayout(size: CellSize, light: Bool) {
        let surface = DefaultRenderer().render(
            ChoiceExampleView(light: light).environment(\.terminalSize, size),
            proposal: .init(width: size.width, height: size.height), frameInstant: .zero
        ).rasterSurface
        let text = surface.lines.joined(separator: "\n")
        #expect(surface.size == size)
        #expect(text.contains("/ choices"))
        #expect(text.contains("1 / 2"))
        #expect(text.contains("Language"))
        #expect(text.contains("Swift"))
        #expect(text.contains("Next"))
        #expect(text.contains("Cancel"))
        #expect(text.contains("^S next"))
        #expect(text.contains("^T theme"))
        #expect(text.contains("^Q quit"))
        #expect(!text.contains("Error:"))
        let theme: ChioTheme = light ? .light : .default
        #expect(surface.cells.flatMap { $0 }.contains {
            $0.character == "L" && $0.style?.foregroundColor == theme.colors.heading
        })
    }

    @Test("Multi-choice errors retain save, back, cancel and help at narrow sizes",
          arguments: [CellSize(width: 100, height: 30), CellSize(width: 50, height: 30),
                      CellSize(width: 36, height: 18)], [false, true])
    func capabilitiesLayout(size: CellSize, light: Bool) {
        let surface = DefaultRenderer().render(
            ChoiceExampleView(light: light, initialStep: .capabilities, showsValidation: true)
                .environment(\.terminalSize, size),
            proposal: .init(width: size.width, height: size.height), frameInstant: .zero
        ).rasterSurface
        let text = surface.lines.joined(separator: "\n")
        #expect(surface.size == size)
        #expect(text.contains("2 / 2"))
        #expect(text.contains("Capabilities"))
        #expect(text.contains("Build"))
        #expect(text.contains("Error: Choose at least 1"))
        #expect(text.contains("Save"))
        #expect(text.contains("Back"))
        #expect(text.contains("Cancel"))
        #expect(text.contains("esc clear"))
        #expect(text.contains("^S save"))
        #expect(text.contains("^X cancel"))
        #expect(text.contains("^T theme"))
        #expect(text.contains("^Q quit"))
        if size.height >= 30 {
            #expect(text.contains("Deploy"))
            #expect(text.contains("Unavailable"))
        }
    }
}
