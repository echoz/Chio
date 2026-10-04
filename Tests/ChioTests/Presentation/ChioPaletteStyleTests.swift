import Chio
import SwiftTUIRuntime
import Testing

@MainActor
struct ChioPaletteStyleTests {
    @Test("Long command lists keep keyboard selection visible and activate from a batch")
    func selectionWindow() async throws {
        let recorder = HostedFrameRecorder()
        let surface = HostedRasterSurface(surfaceSize: .init(width: 36, height: 18), appearance: .fallback,
                                          onFrame: { recorder.receive($0) })
        let session = try HostedSceneSession(for: PaletteStyleTestApp(), sceneID: "palette-style", surface: surface)
        let run = Task { try await session.start() }
        defer { session.stop() }
        do {
            let first = try await recorder.wait(description: "initial Alpha selection") { frame in
                frame.raster.lines.contains { $0.contains("› Alpha") }
                    && frame.semantics.accessibilityNodes.contains {
                        $0.identity == frame.focusedIdentity && $0.role == .textField
                    }
            }
            #expect(!first.raster.lines.contains { $0.contains("Mu") })
            for _ in 0..<11 { session.send(.key(.arrowDown)) }
            let last = try await recorder.wait(after: first.sequence, description: "last command is visible") {
                $0.raster.lines.contains { $0.contains("› Mu") }
            }
            #expect(!last.raster.lines.contains { $0.contains("Alpha") })
            #expect(last.raster.lines.contains { $0.contains("esc close") })
            session.sendInput(Array("Alpha\r\r".utf8))
            let selected = try await recorder.wait(after: last.sequence, description: "typed query and Return activate once") {
                $0.raster.lines.contains { $0.contains("Chosen Alpha: 1") }
            }
            #expect(!selected.semantics.accessibilityNodes.contains { $0.role == .textField })
            session.stop()
            #expect(try await run.value == .inputEnded)
        } catch {
            session.stop()
            _ = await run.result
            throw error
        }
    }

    @Test("Native palettes inherit customized Chio tokens through the theme modifier",
          arguments: [false, true])
    func themedPalette(light: Bool) async throws {
        var theme = light ? ChioTheme.light : .default
        theme.colors.heading = Color(hexRGB: 0x123456)
        theme.colors.accent = Color(hexRGB: 0xA65432)
        theme.colors.selectedSurface = Color(hexRGB: 0x654321)
        let recorder = HostedFrameRecorder()
        let surface = HostedRasterSurface(surfaceSize: .init(width: 36, height: 18), appearance: .fallback,
                                          onFrame: { recorder.receive($0) })
        let session = try HostedSceneSession(for: PaletteStyleTestApp(theme: theme), sceneID: "palette-style", surface: surface)
        let run = Task { try await session.start() }
        defer { session.stop() }
        do {
            let frame = try await recorder.wait(description: "custom palette and native filter focus") { frame in
                frame.raster.lines.contains { $0.contains("› Alpha") }
                    && frame.semantics.accessibilityNodes.contains {
                        $0.identity == frame.focusedIdentity && $0.role == .textField
                            && $0.label == "Filter commands…"
                    }
            }
            let cells = frame.raster.cells.flatMap { $0 }
            #expect(cells.contains {
                $0.character == "C" && $0.style?.foregroundColor == theme.colors.heading
                    && $0.style?.backgroundColor == theme.colors.surface
            })
            #expect(cells.contains {
                $0.character == "›" && $0.style?.foregroundColor == theme.colors.accent
                    && $0.style?.backgroundColor == theme.colors.selectedSurface
            })
            #expect(cells.contains {
                $0.character == "A" && $0.style?.foregroundColor == theme.colors.foreground
                    && $0.style?.backgroundColor == theme.colors.selectedSurface
            })
            #expect(frame.raster.lines.contains { $0.contains("esc close") })
            session.stop()
            #expect(try await run.value == .inputEnded)
        } catch {
            session.stop()
            _ = await run.result
            throw error
        }
    }
}

private struct PaletteStyleTestApp {
    let theme: ChioTheme

    nonisolated init() { theme = .default }
    nonisolated init(theme: ChioTheme) { self.theme = theme }
}

extension PaletteStyleTestApp: App {
    var body: some Scene {
        WindowGroup(id: "palette-style") { PaletteStyleTestView(theme: theme) }.exitOnKeys([])
    }
}

@MainActor
private struct PaletteStyleTestView {
    let theme: ChioTheme
    @State private var isPresented = true
    @State private var activations = 0
}

extension PaletteStyleTestView: View {
    var body: some View {
        Text("Chosen Alpha: \(activations)")
            .panel(id: "palette-style")
            .paletteCommand(name: "Alpha") { activations += 1 }
            .paletteCommand(name: "Beta") {}
            .paletteCommand(name: "Gamma") {}
            .paletteCommand(name: "Delta") {}
            .paletteCommand(name: "Epsilon") {}
            .paletteCommand(name: "Zeta") {}
            .paletteCommand(name: "Eta") {}
            .paletteCommand(name: "Theta") {}
            .paletteCommand(name: "Iota") {}
            .paletteCommand(name: "Kappa") {}
            .paletteCommand(name: "Lambda") {}
            .paletteCommand(name: "Mu") {}
            .paletteSheet("Commands", isPresented: $isPresented)
            .chioTheme(theme)
    }
}
