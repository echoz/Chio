import Chio
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct ChioButtonStyleTests {
    @Test("Native button focus fills its entire bounds and clears on Tab", arguments: [false, true])
    func wholeButtonFill(light: Bool) async throws {
        let theme: ChioTheme = light ? .light : .default
        let recorder = HostedFrameRecorder()
        let surface = HostedRasterSurface(surfaceSize: .init(width: 36, height: 18), appearance: .fallback,
                                          onFrame: { recorder.receive($0) })
        let session = try HostedSceneSession(for: ButtonTestApp(light: light), sceneID: "button-fill", surface: surface)
        let run = Task { try await session.start() }
        do {
            _ = try await recorder.wait(description: "initial native focus") { $0.buttonFocused("Publish") }
            session.send(.key(.tab))
            let moved = try await recorder.wait(description: "native focus moves to Remove") { $0.buttonFocused("Remove") }
            session.send(.key(.tab, modifiers: .shift))
            let initial = try await recorder.wait(after: moved.sequence, description: "Publish receives native focus and its outline") {
                $0.buttonFocused("Publish") && $0.buttonOutline("Publish", color: theme.colors.accent)
            }
            try expectFill(initial, label: "Publish", background: theme.colors.selectedSurface, border: theme.colors.accent)
            try expectFill(initial, label: "Remove", background: theme.colors.surface, border: theme.colors.border)
            let disabled = try #require(initial.semantics.accessibilityNodes.first { $0.label == "Unavailable" })
            #expect(!disabled.isEnabled)
            #expect(!initial.semantics.focusRegions.contains { $0.identity == disabled.identity })
            let disabledFill = try #require(initial.raster.cells[disabled.rect.origin.y + 1][disabled.rect.origin.x + 1].style?.backgroundColor)
            try expectFill(initial, label: "Unavailable", background: disabledFill)

            session.send(.key(.tab))
            let removed = try await recorder.wait(after: initial.sequence, description: "Tab transfers focus to destructive action") {
                $0.buttonFocused("Remove") && $0.buttonOutline("Remove", color: theme.colors.error)
            }
            try expectFill(removed, label: "Publish", background: theme.colors.surface, border: theme.colors.border)
            try expectFill(removed, label: "Remove", background: theme.colors.selectedSurface, border: theme.colors.error)
            session.send(.key(.tab))
            let quiet = try await recorder.wait(after: removed.sequence, description: "Tab skips disabled action") {
                $0.buttonFocused("Quiet") && $0.buttonOutline("Remove", color: theme.colors.border)
            }
            try expectFill(quiet, label: "Remove", background: theme.colors.surface, border: theme.colors.border)
            try expectFill(quiet, label: "Quiet", background: theme.colors.surface, border: theme.colors.border)
            session.send(.key(.return))
            let activated = try await recorder.wait(after: quiet.sequence, description: "suppressed focus effect retains native activation") {
                $0.raster.lines.contains { $0.contains("Activated=1") }
            }
            #expect(activated.buttonFocused("Quiet"))
            session.stop()
            #expect(try await run.value == .inputEnded)
        } catch {
            session.stop()
            _ = await run.result
            throw error
        }
    }

    private func expectFill(_ frame: SemanticHostFrame, label: String, background: Color, border: Color? = nil) throws {
        let node = try #require(frame.semantics.accessibilityNodes.first { $0.role == .button && $0.label == label })
        let rect = node.rect
        #expect(rect.size.height == 3)
        #expect(rect.size.width == label.count + 4)
        let cells = (rect.origin.y..<rect.maxY).flatMap { y in
            (rect.origin.x..<rect.maxX).map { x in frame.raster.cells[y][x] }
        }
        // Includes the label, padding, all four border sides, and corners.
        #expect(cells.allSatisfy { $0.style?.backgroundColor == background }, "\(label) must have one background across all cells")
        let topLeft = frame.raster.cells[rect.origin.y][rect.origin.x]
        #expect(topLeft.character == "╭")
        if let border { #expect(topLeft.style?.foregroundColor == border) }
    }
}

private struct ButtonTestApp {
    let light: Bool
    nonisolated init() { light = false }
    nonisolated init(light: Bool) { self.light = light }
}

extension ButtonTestApp: App {
    var body: some Scene {
        WindowGroup(id: "button-fill") { ButtonTestView(light: light) }.exitOnKeys([])
    }
}

@MainActor
private struct ButtonTestView {
    let light: Bool
    @State private var activations = 0
}

extension ButtonTestView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Button("Publish") { activations += 1 }
            Button("Remove", role: .destructive) { activations += 1 }
            Button("Unavailable") { activations += 1 }.disabled(true)
            Button("Quiet") { activations += 1 }.focusEffectDisabled()
            Text("Activated=\(activations)")
        }
        .chioTheme(light ? .light : .default)
    }
}

private extension SemanticHostFrame {
    func buttonFocused(_ label: String) -> Bool {
        semantics.accessibilityNodes.contains { $0.identity == focusedIdentity && $0.label == label }
    }

    func buttonOutline(_ label: String, color: Color) -> Bool {
        guard let node = semantics.accessibilityNodes.first(where: { $0.role == .button && $0.label == label }) else { return false }
        return raster.cells[node.rect.origin.y][node.rect.origin.x].style?.foregroundColor == color
    }
}
