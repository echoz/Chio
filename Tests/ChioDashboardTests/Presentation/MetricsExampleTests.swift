@testable import ChioDashboard
import Chio
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct MetricsExampleTests {
    @Test("Simulated metrics retain both panels, gauges, native actions and hints at wide and compact sizes",
          arguments: [CellSize(width: 100, height: 30), CellSize(width: 70, height: 24),
                      CellSize(width: 50, height: 24), CellSize(width: 36, height: 18)], ExampleTheme.allCases)
    func layout(size: CellSize, appearance: ExampleTheme) {
        let rendered = DefaultRenderer().render(
            MetricsExampleView(theme: appearance).environment(\.terminalSize, size),
            proposal: .init(width: size.width, height: size.height)
        )
        let text = rendered.rasterSurface.lines.joined(separator: "\n")
        #expect(rendered.rasterSurface.size == size)
        for value in ["metrics", "simulated", "Processor", "Memory", "CPU", "RAM", "62%", "71%",
                      "Next sample", "History", "n next", "g history", "^T theme", "^Q quit"] {
            #expect(text.contains(value))
        }
        let nodes = rendered.semanticSnapshot.accessibilityNodes
        for label in ["Next sample", "Cycle history"] {
            #expect(nodes.contains { $0.role == .button && $0.label == label && $0.isEnabled })
        }
        #expect(nodes.contains { $0.label == "CPU utilization: 62 percent" })
        #expect(nodes.contains { $0.label == "RAM utilization: 71 percent" })
        #expect(nodes.contains { $0.label == "Processor history, simulated, full, 0 to 100 percent. 24 readings, 0 missing. Latest: 62 percent. Minimum: 22 percent. Maximum: 100 percent." })
        #expect(nodes.contains { $0.label == "Memory history, simulated, full, 0 to 100 percent. 24 readings, 0 missing. Latest: 71 percent. Minimum: 48 percent. Maximum: 71 percent." })
        let theme = appearance.theme
        #expect(rendered.rasterSurface.cells.flatMap { $0 }.contains {
            $0.character == "6" && $0.style?.foregroundColor == theme.colors.accent
        })
    }

    @Test("Native actions, shortcuts, theme cycling and resize preserve simulated values and focus")
    func workflow() async throws {
        let recorder = HostedFrameRecorder()
        let surface = HostedRasterSurface(surfaceSize: .init(width: 100, height: 30), appearance: .fallback,
                                          onFrame: { recorder.receive($0) })
        let session = try HostedSceneSession(for: MetricsTestApp(), sceneID: "metrics-tests", surface: surface)
        let run = Task { try await session.start() }
        do {
            let initial = try await recorder.wait(description: "native Next sample is initially focused") {
                $0.metricsFocused("Next sample") && $0.metricsValue("CPU", 62) && $0.metricsValue("RAM", 71)
            }
            session.send(.key(.return))
            let stepped = try await recorder.wait(after: initial.sequence, description: "Return advances one local sample") {
                $0.metricsFocused("Next sample") && $0.metricsValue("CPU", 22) && $0.metricsValue("RAM", 48)
            }
            session.send(.key(.tab))
            let historyFocus = try await recorder.wait(after: stepped.sequence, description: "native Tab reaches history action") {
                $0.metricsFocused("Cycle history")
            }
            session.send(.key(.return))
            let gaps = try await recorder.wait(after: historyFocus.sequence, description: "native History activates the gaps variant") {
                $0.metricsHistory("gaps") && $0.metricsFocused("Cycle history")
                    && $0.metricsValue("CPU", 22) && $0.metricsValue("RAM", 48)
            }
            session.send(.key(.character("g")))
            let empty = try await recorder.wait(after: gaps.sequence, description: "history shortcut selects empty graphs without clearing current gauges") {
                $0.metricsHistory("empty") && $0.metricsValue("CPU", 22) && $0.metricsValue("RAM", 48)
            }
            session.send(.key(.character("n")))
            let advancedEmpty = try await recorder.wait(after: empty.sequence, description: "samples advance even while history is empty") {
                $0.metricsHistory("empty") && $0.metricsValue("CPU", 28) && $0.metricsValue("RAM", 48)
            }
            var paletteFrame = advancedEmpty
            for _ in 0..<3 {
                session.send(.key(.character("t"), modifiers: .ctrl))
                let preceding = paletteFrame
                paletteFrame = try await recorder.wait(after: preceding.sequence, description: "palette cycle retains values, history mode and native focus") {
                    $0.metricsHistory("empty") && $0.metricsValue("CPU", 28) && $0.metricsValue("RAM", 48)
                        && $0.metricsFocused("Cycle history") && $0.focusedIdentity == preceding.focusedIdentity
                        && $0.raster.cells != preceding.raster.cells
                }
            }
            #expect(paletteFrame.raster.cells == advancedEmpty.raster.cells)
            surface.updateSurfaceSize(.init(width: 36, height: 18))
            session.requestSurfaceRefresh()
            let narrow = try await recorder.wait(after: paletteFrame.sequence, description: "compact stacking retains native history focus and visible hints") {
                $0.raster.size == CellSize(width: 36, height: 18) && $0.metricsFocused("Cycle history")
                    && $0.metricsHistory("empty") && $0.metricsValue("CPU", 28) && $0.metricsValue("RAM", 48)
                    && $0.raster.lines.contains { $0.contains("^Q quit") }
            }
            session.send(.key(.return))
            let restored = try await recorder.wait(after: narrow.sequence, description: "native action restores the retained populated history") {
                $0.metricsHistory("full") && $0.metricsFocused("Cycle history") && $0.metricsValue("CPU", 28)
            }
            session.sendInput(Array("nn\t".utf8))
            _ = try await recorder.wait(after: restored.sequence, description: "batched next shortcuts retain each step before native Tab") {
                $0.metricsFocused("Next sample") && $0.metricsValue("CPU", 36) && $0.metricsValue("RAM", 50)
                    && $0.metricsHistory("full")
            }
            session.stop()
            #expect(try await run.value == .inputEnded)
        } catch {
            session.stop()
            if case .failure(let runError) = await run.result {
                Issue.record("Hosted metrics failed: \(runError)")
            }
            throw error
        }
    }
}

private struct MetricsTestApp {
    nonisolated init() {}
}

extension MetricsTestApp: App {
    var body: some Scene {
        WindowGroup(id: "metrics-tests") { MetricsExampleView() }.exitOnKeys([])
    }
}

private extension SemanticHostFrame {
    func metricsFocused(_ label: String) -> Bool {
        semantics.accessibilityNodes.contains {
            $0.identity == focusedIdentity && $0.role == .button && $0.label == label
        }
    }

    func metricsValue(_ label: String, _ percent: Int) -> Bool {
        semantics.accessibilityNodes.contains { $0.label == "\(label) utilization: \(percent) percent" }
    }

    func metricsHistory(_ mode: String) -> Bool {
        ["Processor", "Memory"].allSatisfy { title in
            semantics.accessibilityNodes.contains {
                $0.label?.hasPrefix("\(title) history, simulated, \(mode), 0 to 100 percent.") == true
                    && $0.label?.contains(mode == "empty" ? "No readings." : mode == "gaps" ? "21 readings, 3 missing." : "24 readings, 0 missing.") == true
            }
        }
    }
}
