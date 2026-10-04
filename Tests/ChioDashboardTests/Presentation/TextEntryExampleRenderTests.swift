@testable import ChioDashboard
import Chio
import SwiftTUIRuntime
import Testing

@MainActor
struct TextEntryExampleRenderTests {
    @Test("Native text fields, actions and hints remain visible across sizes and themes",
          arguments: [CellSize(width: 100, height: 30), CellSize(width: 50, height: 30),
                      CellSize(width: 36, height: 18)], [false, true])
    func layout(size: CellSize, light: Bool) {
        let syntheticPassword = "Fixture-password-482!"
        let rendered = DefaultRenderer().render(
            TextEntryExampleView(light: light, initialPassword: syntheticPassword, initialNotes: "First note\nSecond note")
                .environment(\.terminalSize, size),
            proposal: .init(width: size.width, height: size.height), frameInstant: .zero
        )
        let surface = rendered.rasterSurface
        let text = surface.lines.joined(separator: "\n")
        let concealsPassword = !text.contains(syntheticPassword)
            && !String(reflecting: rendered.semanticSnapshot).contains(syntheticPassword)
        #expect(concealsPassword)
        #expect(surface.size == size)
        #expect(text.contains("/ text entry"))
        #expect(text.contains("Demo password"))
        #expect(text.contains("•"))
        #expect(text.contains("Notes"))
        #expect(text.contains("First note"))
        #expect(text.contains("Second note"))
        #expect(text.contains("Save") && text.contains("Cancel"))
        #expect(text.contains("^S save") && text.contains("^X cancel"))
        #expect(text.contains("^D lock") && text.contains("^T theme") && text.contains("^Q quit"))
        #expect(!text.contains("Error:"))
        #expect(rendered.semanticSnapshot.accessibilityNodes.contains { $0.role == .secureField })
        #expect(rendered.semanticSnapshot.accessibilityNodes.contains { $0.role == .textEditor })
        let theme: ChioTheme = light ? .light : .default
        #expect(surface.cells.flatMap { $0 }.contains {
            $0.character == "D" && $0.style?.foregroundColor == theme.colors.heading
        })
    }

    @Test("Inline validation retains both controls and essential actions on short terminals",
          arguments: [CellSize(width: 100, height: 30), CellSize(width: 50, height: 30),
                      CellSize(width: 36, height: 18)], [false, true])
    func validationLayout(size: CellSize, light: Bool) {
        let rendered = DefaultRenderer().render(
            TextEntryExampleView(light: light, showsValidation: true).environment(\.terminalSize, size),
            proposal: .init(width: size.width, height: size.height), frameInstant: .zero
        )
        let text = rendered.rasterSurface.lines.joined(separator: "\n")
        #expect(text.contains("Demo password") && text.contains("Notes"))
        #expect(text.contains("Error: Use at least 8 characters."))
        #expect(text.contains("Error: Enter some notes."))
        #expect(text.contains("Save") && text.contains("Cancel"))
        #expect(text.contains("^S save") && text.contains("^X cancel"))
        #expect(text.contains("^D lock") && text.contains("^T theme") && text.contains("^Q quit"))
    }

    @Test("Locked controls conceal their value and keep unlock and cancel available", arguments: [false, true])
    func lockedLayout(light: Bool) {
        let size = CellSize(width: 36, height: 18)
        let syntheticPassword = "Fixture-password-482!"
        let rendered = DefaultRenderer().render(
            TextEntryExampleView(light: light, initialPassword: syntheticPassword, initialNotes: "Local notes",
                                 inputsDisabled: true).environment(\.terminalSize, size),
            proposal: .init(width: size.width, height: size.height), frameInstant: .zero
        )
        let text = rendered.rasterSurface.lines.joined(separator: "\n")
        let concealsPassword = !text.contains(syntheticPassword)
            && !String(reflecting: rendered.semanticSnapshot).contains(syntheticPassword)
        #expect(concealsPassword)
        #expect(text.contains("Inputs locked"))
        #expect(text.contains("^D unlock") && text.contains("^X cancel"))
        #expect(text.contains("Local notes") && text.contains("Cancel"))
    }
}
