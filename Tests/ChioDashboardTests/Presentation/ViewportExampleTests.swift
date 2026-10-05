@testable import ChioDashboard
import Chio
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct ViewportExampleTests {
    @Test("The activity viewport retains content, native tracks and actions in both themes",
          arguments: [CellSize(width: 100, height: 30), CellSize(width: 50, height: 30),
                      CellSize(width: 36, height: 18)], [false, true])
    func layout(size: CellSize, light: Bool) {
        let rendered = DefaultRenderer().render(
            ViewportExampleView(light: light).environment(\.terminalSize, size),
            proposal: .init(width: size.width, height: size.height), frameInstant: .zero
        )
        let text = rendered.rasterSurface.lines.joined(separator: "\n")
        #expect(rendered.rasterSurface.size == size)
        #expect(text.contains("/ activity viewport"))
        #expect(text.contains("Build agent"))
        #expect(text.contains("Back to start") && text.contains("Row 1 · Col 1"))
        #expect(text.contains("^Q quit"))
        #expect(text.contains("▐") && text.contains("▂"))
        #expect(rendered.semanticSnapshot.scrollRoutes.count == 1)
    }

    @Test("Passive log rows retain fixed columns, semantic emphasis and full scroll extent",
          arguments: [false, true])
    func eventColumns(light: Bool) throws {
        let size = CellSize(width: 100, height: 30)
        let rendered = DefaultRenderer().render(
            ViewportExampleView(light: light).environment(\.terminalSize, size),
            proposal: .init(width: size.width, height: size.height), frameInstant: .zero
        )
        let y = try #require(rendered.rasterSurface.lines.firstIndex { $0.contains("01  ✓  Build agent") })
        let row = rendered.rasterSurface.cells[y]
        let x = try #require(row.firstIndex { $0.character == "0" })
        let theme: ChioTheme = light ? .light : .default
        #expect(String(row[x..<(x + 2)].map(\.character)) == "01")
        #expect(row[x + 4].character == "✓")
        #expect(String(row[(x + 7)..<(x + 18)].map(\.character)) == "Build agent")
        #expect(String(row[(x + 21)..<(x + 43)].map(\.character)) == "Compiled the workspace")
        #expect(String(row[(x + 81)..<(x + 83)].map(\.character)) == "ru")
        #expect(row[x].style?.foregroundColor == theme.colors.mutedText)
        #expect(row[x + 4].style?.foregroundColor == theme.colors.success)
        #expect(row[x + 7].style?.emphasis.contains(.bold) == true)
        #expect(row[x + 21].style?.emphasis.contains(.bold) != true)
        #expect(row[x + 81].style?.foregroundColor == theme.colors.secondaryText)
        let route = try #require(rendered.semanticSnapshot.scrollRoutes.first)
        #expect(route.contentBounds.size.width == 96 && route.contentBounds.size.height == 40)
        #expect(rendered.semanticSnapshot.accessibilityNodes.contains {
            $0.label?.hasPrefix("01  ✓  Build agent") == true && $0.label?.hasSuffix("run 1001") == true
        })
    }

    @Test("Native scrolling survives theme and resize, with focus and reset handled by native controls")
    func viewportWorkflow() async throws {
        let recorder = HostedFrameRecorder()
        let surface = HostedRasterSurface(surfaceSize: .init(width: 100, height: 30), appearance: .fallback,
                                          onFrame: { recorder.receive($0) })
        let session = try HostedSceneSession(for: ViewportTestApp(), sceneID: "viewport-tests", surface: surface)
        let run = Task { try await session.start() }
        do {
            _ = try await recorder.wait(description: "log starts with native viewport focus") { $0.logFocused && $0.logContains("Row 2 · Col 2") }
            session.send([.key(.home), .key(.arrowLeft)])
            _ = try await recorder.wait(description: "native keys establish the log origin") { $0.logContains("Row 1 · Col 1") }
            session.send([.key(.arrowDown), .key(.arrowDown), .key(.arrowRight)])
            let moved = try await recorder.wait(description: "native arrows scroll both axes") {
                $0.logContains("Row 3 · Col 2") && $0.semantics.scrollRoutes.first?.contentOffset == .init(x: 1, y: 2)
            }
            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(after: moved.sequence, description: "theme retains position and focus") {
                $0.logFocused && $0.logContains("Row 3 · Col 2") && $0.raster.cells != moved.raster.cells
            }
            surface.updateSurfaceSize(.init(width: 36, height: 18))
            session.requestSurfaceRefresh()
            _ = try await recorder.wait(after: themed.sequence, description: "compact viewport retains position and shortcuts") {
                $0.raster.size == CellSize(width: 36, height: 18) && $0.logContains("Row 3 · Col 2")
                    && $0.logContains("^Q quit") && $0.logFocused
            }
            session.send(.key(.end))
            _ = try await recorder.wait(description: "End reaches the last event") {
                guard let route = $0.semantics.scrollRoutes.first else { return false }
                return route.contentOffset.y == route.contentBounds.size.height - route.viewportRect.size.height
                    && $0.logContains("Docs agent")
            }
            session.send(.key(.home))
            var current = try await recorder.wait(description: "Home returns vertically without resetting horizontal position") {
                $0.logContains("Row 1 · Col 2")
            }
            for _ in 0..<4 {
                if current.logResetFocused { break }
                session.send(.key(.tab))
                let previousFocus = current.focusedIdentity
                current = try await recorder.wait(after: current.sequence, description: "Tab advances native viewport focus") {
                    $0.focusedIdentity != nil && $0.focusedIdentity != previousFocus
                }
            }
            #expect(current.logResetFocused)
            session.send(.key(.return))
            _ = try await recorder.wait(description: "native reset action restores both offsets") {
                $0.logResetFocused && $0.logContains("Row 1 · Col 1")
            }
            session.send(.key(.functionKey(6)))
            _ = try await recorder.wait(description: "F6 restores log focus with native track reveal") { $0.logFocused && $0.logContains("Row 2 · Col 2") }
            session.send(.key(.arrowDown))
            _ = try await recorder.wait(description: "native input still works after focus restoration") { $0.logContains("Row 3 · Col 2") }
            session.stop()
            #expect(try await run.value == .inputEnded)
        } catch {
            session.stop()
            if case .failure(let runError) = await run.result {
                Issue.record("Hosted viewport failed: \(runError)")
            }
            throw error
        }
    }
}

private struct ViewportTestApp {
    nonisolated init() {}
}

extension ViewportTestApp: App {
    var body: some Scene {
        WindowGroup(id: "viewport-tests") { ViewportExampleView() }.exitOnKeys([])
    }
}

private extension SemanticHostFrame {
    func logContains(_ value: String) -> Bool { raster.lines.contains { $0.contains(value) } }
    var logFocused: Bool {
        semantics.accessibilityNodes.contains { $0.identity == focusedIdentity && $0.role == .scrollViewWithIndicators }
    }
    var logResetFocused: Bool {
        semantics.accessibilityNodes.contains { $0.identity == focusedIdentity && $0.role == .button && $0.label == "Back to start" }
    }
}
