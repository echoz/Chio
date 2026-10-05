import Chio
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct ChioCompactStyleTests {
    @Test("Compact titles preserve corners and hide their paint in tiny allocations", arguments: 0...6)
    func tinyTitle(width: Int) {
        let rendered = DefaultRenderer().render(
            GroupBox("ABCDEFGHIJKLMNOPQRSTUVWXYZ") { Text(".").frame(maxWidth: .infinity) }
                .groupBoxStyle(ChioGroupBoxStyle(titlePlacement: .border))
                .frame(width: width, height: 3, alignment: .topLeading)
                .clipped(),
            proposal: .init(width: width, height: 3)
        )
        let surface = rendered.rasterSurface
        #expect(surface.size.width <= width)
        #expect(surface.size.height <= 3)
        if width < 5 {
            #expect(!surface.cells.flatMap { $0 }.contains {
                $0.style?.foregroundColor == ChioTheme.default.colors.heading
            })
        } else {
            #expect(surface.lines.first?.hasPrefix("╭") == true)
            #expect(surface.lines.first?.hasSuffix("╮") == true)
        }
    }

    @Test("Compact Unicode titles mask only their title and retain content and border paint",
          arguments: [ChioTheme.default, .light, .btop])
    func titlePaint(theme: ChioTheme) throws {
        let surface = DefaultRenderer().render(
            GroupBox("界 e\u{301} instrumentation and history") {
                Text("Ready").frame(width: 28, alignment: .leading)
            }
            .groupBoxStyle(ChioGroupBoxStyle(theme: theme, titlePlacement: .border)),
            proposal: .init(width: 32, height: nil)
        ).rasterSurface
        let top = try #require(surface.lines.first)
        #expect(top.hasPrefix("╭ "))
        #expect(top.hasSuffix("╮"))
        #expect(top.contains("界"))
        #expect(top.contains("…"))
        #expect(surface.lines.contains { $0.contains("Ready") })
        #expect(surface.size.width == 32)
        #expect(surface.size.height == 3, "Actual frame: \(surface.size), \(surface.lines)")
        #expect(surface.cells[0][0].style?.foregroundColor == theme.colors.border)
        #expect(surface.cells[0][2].style?.foregroundColor == theme.colors.heading)
        #expect(surface.cells[0][1].style?.backgroundColor == theme.colors.surface)
    }

    @Test("Border titles consume no additional content row and absence preserves the same allocation")
    func titleAllocation() {
        let renderer = DefaultRenderer()
        let labeled = renderer.render(
            GroupBox("Metrics") { Text("Ready").frame(width: 20) }
                .groupBoxStyle(ChioGroupBoxStyle(titlePlacement: .border)),
            proposal: .init(width: 24, height: 8)
        ).rasterSurface
        let unlabeled = renderer.render(
            GroupBox { Text("Ready").frame(width: 20) }
                .groupBoxStyle(ChioGroupBoxStyle(titlePlacement: .border)),
            proposal: .init(width: 24, height: 8)
        ).rasterSurface
        #expect(labeled.size == unlabeled.size)
        #expect(labeled.lines[1] == unlabeled.lines[1])
        #expect(labeled.lines.last == unlabeled.lines.last)
        #expect(labeled.lines[0].contains("Metrics"))
        #expect(labeled.lines[0].contains("─"))
    }

    @Test("Compact title controls are passive while content keeps native focus and pointer bounds",
          arguments: [24, 48])
    func passiveTitle(width: Int) throws {
        let rendered = DefaultRenderer().render(
            GroupBox {
                Button("Run") {}
            } label: {
                Button("Title") {}
            }
            .groupBoxStyle(ChioGroupBoxStyle(titlePlacement: .border))
            .frame(width: width, height: 7, alignment: .topLeading),
            proposal: .init(width: width, height: 7)
        )
        let semantics = rendered.semanticSnapshot
        let title = try #require(semantics.accessibilityNodes.first { $0.role == .button && $0.label == "Title" })
        let run = try #require(semantics.accessibilityNodes.first { $0.role == .button && $0.label == "Run" })
        #expect(!title.isEnabled)
        #expect(run.isEnabled)
        #expect(!semantics.focusRegions.contains { $0.identity == title.identity })
        #expect(semantics.focusRegions.contains { $0.identity == run.identity })
        #expect(!semantics.interactionRegions.contains { $0.identity == title.identity })
        #expect(semantics.interactionRegions.contains { $0.identity == run.identity })
        for region in semantics.interactionRegions {
            #expect(region.rect.origin.x >= 0 && region.rect.maxX <= width)
            #expect(region.rect.origin.y >= 0 && region.rect.maxY <= 7)
        }
    }

    @Test("Native activation reaches compact content and skips the display-only title")
    func contentActivation() async throws {
        let recorder = HostedFrameRecorder()
        let surface = HostedRasterSurface(surfaceSize: .init(width: 32, height: 10), appearance: .fallback,
                                          onFrame: { recorder.receive($0) })
        let session = try HostedSceneSession(for: CompactGroupTestApp(), sceneID: "compact-group", surface: surface)
        let task = Task { try await session.start() }
        do {
            let initial = try await recorder.wait(description: "compact content receives native focus") { frame in
                frame.semantics.accessibilityNodes.contains {
                    $0.role == .button && $0.label == "Run" && $0.identity == frame.focusedIdentity
                }
            }
            session.send(.key(.return))
            let activated = try await recorder.wait(after: initial.sequence, description: "compact content activates") {
                $0.raster.lines.contains { $0.contains("Count=1") }
            }
            session.send(.key(.tab))
            let moved = try await recorder.wait(after: activated.sequence, description: "native Tab skips compact title") { frame in
                frame.semantics.accessibilityNodes.contains {
                    $0.role == .button && $0.label == "Next" && $0.identity == frame.focusedIdentity
                }
            }
            #expect(!moved.semantics.focusRegions.contains { region in
                moved.semantics.accessibilityNodes.contains {
                    $0.identity == region.identity && $0.label == "Title"
                }
            })
            session.stop()
            #expect(try await task.value == .inputEnded)
        } catch {
            session.stop()
            _ = await task.result
            throw error
        }
    }

    @Test("Full measurement retains accent while full progress remains semantic success",
          arguments: [ChioTheme.default, .light, .btop], [0.0, 0.5, 1.0])
    func measurement(theme: ChioTheme, value: Double) throws {
        for treatment in [ChioProgressViewStyle.Treatment.progress, .measurement] {
            let rendered = DefaultRenderer().render(
                ProgressView(value: value, barWidth: 8) { Text("CPU") } currentValueLabel: { Text("percent") }
                    .progressViewStyle(ChioProgressViewStyle(theme: theme, treatment: treatment)),
                proposal: .init(width: 16, height: 2)
            )
            let surface = rendered.rasterSurface
            let track = try #require(surface.lines.last)
            let expected = value == 0 ? "────────" : value == 0.5 ? "━━━━────" : "━━━━━━━━"
            #expect(track.hasPrefix(expected))
            #expect(surface.lines.first?.contains("CPU") == true)
            let color = treatment == .progress && value == 1 ? theme.colors.success : theme.colors.accent
            #expect(surface.cells.flatMap { $0 }.filter { $0.character == "━" }.allSatisfy {
                $0.style?.foregroundColor == color
            })
            #expect(rendered.semanticSnapshot.accessibilityNodes.contains { $0.role == .progressBar })
        }
    }

    @Test("Measurement uses customized glyphs and leaves native indeterminate presentation unchanged")
    func measurementTreatments() {
        let theme = ChioTheme.btop.replacing(treatments: ChioTheme.btop.treatments.replacing(
            progressFilledGlyph: "#", progressEmptyGlyph: "."
        ))
        let measurement = DefaultRenderer().render(
            ProgressView(value: 1, barWidth: 8) { EmptyView() } currentValueLabel: { EmptyView() }
                .progressViewStyle(ChioProgressViewStyle(theme: theme, treatment: .measurement)),
            proposal: .init(width: 8, height: 1)
        ).rasterSurface
        #expect(measurement.lines == ["########"])
        #expect(measurement.cells.flatMap { $0 }.allSatisfy {
            $0.style?.foregroundColor == theme.colors.accent
        })
        let progress = DefaultRenderer().render(
            ProgressView(barWidth: 8)
                .progressViewStyle(ChioProgressViewStyle(theme: theme))
                .environment(\.accessibilityReduceMotion, true),
            proposal: .init(width: 8, height: 1)
        ).rasterSurface
        let indeterminateMeasurement = DefaultRenderer().render(
            ProgressView(barWidth: 8)
                .progressViewStyle(ChioProgressViewStyle(theme: theme, treatment: .measurement))
                .environment(\.accessibilityReduceMotion, true),
            proposal: .init(width: 8, height: 1)
        ).rasterSurface
        #expect(progress.lines == indeterminateMeasurement.lines)
        #expect(progress.cells == indeterminateMeasurement.cells)
    }
}

private struct CompactGroupTestApp {
    nonisolated init() {}
}

extension CompactGroupTestApp: App {
    var body: some Scene {
        WindowGroup(id: "compact-group") { CompactGroupTestView() }.exitOnKeys([])
    }
}

@MainActor
private struct CompactGroupTestView {
    @State private var count = 0
}

extension CompactGroupTestView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupBox {
                Button("Run") { count += 1 }
                Text("Count=\(count)")
            } label: {
                Button("Title") { count += 100 }
            }
            .groupBoxStyle(ChioGroupBoxStyle(titlePlacement: .border))
            Button("Next") {}
        }
    }
}
