@testable import ChioDashboard
import Chio
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct DashboardPaletteTests {
    @Test("Opening from dashboard search restores the native editor and its query")
    func searchFocusRestoration() async throws {
        try await withPaletteScene { session, _, recorder in
            _ = try await dashboard(recorder)
            session.sendInput(Array("/docs".utf8))
            let editing = try await recorder.wait(description: "dashboard search is editing docs") {
                !$0.hasPalette && $0.focusesAnyTextField && $0.hasPaletteText("1 of 4 items")
            }
            _ = try await openPalette(session, recorder)
            session.send(.key(.escape))
            let restored = try await recorder.wait(after: editing.sequence, description: "Escape restores dashboard search focus") {
                !$0.hasPalette && $0.focusedIdentity == editing.focusedIdentity && $0.hasPaletteText("1 of 4 items")
            }
            session.send(.key(.character("q")))
            _ = try await recorder.wait(after: restored.sequence, description: "q edits the restored search field") {
                !$0.hasPalette && $0.focusesAnyTextField && $0.hasPaletteText("docsq")
            }
        }
    }

    @Test("Retry and simulation commands reuse dashboard state transitions")
    func retryAndPause() async throws {
        try await withPaletteScene(scenario: .failed) { session, _, recorder in
            _ = try await dashboard(recorder)
            _ = try await openPalette(session, recorder)
            session.sendInput(Array("retry".utf8))
            _ = try await recorder.wait(description: "retry command selected") {
                $0.paletteQuery == "retry" && $0.hasPaletteText("› Retry selected agent")
            }
            session.send(.key(.return))
            _ = try await recorder.wait(description: "selected agent restarts") {
                !$0.hasPalette && $0.hasPaletteText("0%") && $0.hasPaletteText("● local demo")
            }
            _ = try await openPalette(session, recorder)
            session.sendInput(Array("pause".utf8))
            _ = try await recorder.wait(description: "pause command selected") {
                $0.paletteQuery == "pause" && $0.hasPaletteText("› Pause simulation")
            }
            session.send(.key(.return))
            _ = try await recorder.wait(description: "simulation pauses") {
                !$0.hasPalette && $0.hasPaletteText("○ paused")
            }
        }
    }

    @Test("Palette filtering, keyboard selection and Escape retain dashboard query and focus")
    func filterAndCancel() async throws {
        try await withPaletteScene { session, _, recorder in
            _ = try await dashboard(recorder)
            session.sendInput(Array("/docs\r".utf8))
            let before = try await recorder.wait(description: "filtered Docs results") {
                $0.hasPaletteText("1 of 4 items") && $0.hasSelectedAgent("Docs Agent")
                    && !$0.focusesAnyTextField
            }
            _ = try await openPalette(session, recorder)
            session.sendInput(Array("zzzz".utf8))
            let empty = try await recorder.wait(description: "unmatched palette query") {
                $0.hasPaletteText("No matches") && $0.paletteQuery == "zzzz"
            }
            #expect(empty.focusesPaletteField)
            session.send(.key(.return))
            session.send(.key(.escape))
            let restored = try await recorder.wait(after: empty.sequence, description: "Escape restores filtered results") {
                !$0.hasPalette && $0.hasPaletteText("1 of 4 items") && $0.hasSelectedAgent("Docs Agent")
            }
            #expect(restored.focusedIdentity == before.focusedIdentity)
            let reopened = try await openPalette(session, recorder)
            #expect(reopened.paletteQuery == "")
            session.send(.key(.arrowDown))
            let selected = try await recorder.wait(after: reopened.sequence, description: "Down selects next command") {
                $0.hasPaletteText("› Run selected agent")
            }
            #expect(selected.focusedIdentity == reopened.focusedIdentity)
            session.send(.key(.tab, modifiers: .shift))
            _ = try await recorder.wait(after: selected.sequence, description: "Shift-Tab selects previous command") {
                $0.hasPaletteText("› Create agent")
            }
        }
    }

    @Test("Palette actions hand off to report and creation with native focus", arguments: [false, true])
    func coverActions(fromSearch: Bool) async throws {
        try await withPaletteScene { session, _, recorder in
            _ = try await dashboard(recorder)
            session.sendInput(Array((fromSearch ? "/docs" : "/docs\r").utf8))
            let before = try await recorder.wait(description: "filtered Docs agent before palette") {
                $0.hasPaletteText("1 of 4 items") && $0.hasSelectedAgent("Docs Agent")
                    && $0.focusesAnyTextField == fromSearch
                    && !$0.hasPaletteText("Build Agent")
            }
            _ = try await openPalette(session, recorder)
            session.sendInput(Array("report".utf8))
            _ = try await recorder.wait(description: "report command selected") {
                $0.paletteQuery == "report" && $0.hasPaletteText("› Open agent report")
            }
            session.send(.key(.return))
            let report = try await recorder.wait(description: "palette hands off to report") {
                !$0.hasPalette && $0.hasPaletteText("/ agent report") && $0.hasPaletteText("Docs Agent")
            }
            #expect(report.focusedIdentity != nil)
            session.send(.key(.escape))
            let restored = try await recorder.wait(after: report.sequence, description: "report closes to results") {
                !$0.hasPalette && $0.hasPaletteText("/ agent workspace") && !$0.hasPaletteText("/ agent report")
            }
            #expect(restored.focusedIdentity == before.focusedIdentity)
            let reopened = try await openPalette(session, recorder)
            #expect(reopened.paletteQuery == "")
            #expect(reopened.hasPaletteText("› Create agent"))
            session.send(.key(.return))
            _ = try await recorder.wait(description: "palette hands off to Name editor") { frame in
                !frame.hasPalette && frame.hasPaletteText("/ create agent")
                    && frame.semantics.accessibilityNodes.contains {
                        $0.identity == frame.focusedIdentity && $0.role == .textField && $0.label == "Agent name"
                    }
            }
            session.sendInput(Array("Palette Agent".utf8))
            _ = try await recorder.wait(description: "native form editing after palette") {
                $0.hasPaletteText("Palette Agent")
            }
            session.send(.key(.escape))
            let canceled = try await recorder.wait(description: "creation cancel restores dashboard") {
                !$0.hasPalette && $0.hasPaletteText("/ agent workspace") && !$0.hasPaletteText("/ create agent")
            }
            #expect(canceled.focusedIdentity == before.focusedIdentity)
            #expect(canceled.hasPaletteText("1 of 4 items"))
        }
    }

    @Test("Palette works on narrow terminals and applies the chosen theme")
    func narrowAndTheme() async throws {
        try await withPaletteScene { session, surface, recorder in
            _ = try await dashboard(recorder)
            let initial = try await openPalette(session, recorder)
            session.sendInput(Array("theme".utf8))
            let filtered = try await recorder.wait(description: "theme command filtered") {
                $0.paletteQuery == "theme" && $0.hasPaletteText("Switch to light theme")
            }
            surface.updateSurfaceSize(.init(width: 36, height: 18))
            session.requestSurfaceRefresh()
            let narrow = try await recorder.wait(after: filtered.sequence, description: "palette fits narrow terminal") {
                $0.raster.size == CellSize(width: 36, height: 18) && $0.paletteQuery == "theme"
            }
            #expect(narrow.focusedIdentity == initial.focusedIdentity)
            #expect(narrow.hasPaletteText("Switch to light theme"))
            #expect(narrow.hasPaletteText("esc"))
            session.send(.key(.return))
            _ = try await recorder.wait(description: "theme action dismisses palette") { !$0.hasPalette }
            let light = try await openPalette(session, recorder)
            #expect(light.raster.cells.flatMap { $0 }.contains {
                $0.style?.backgroundColor == ChioTheme.light.colors.surface
            })
            session.sendInput(Array("theme".utf8))
            _ = try await recorder.wait(description: "theme command reflects changed state") {
                $0.hasPaletteText("Switch to dark theme")
            }
        }
    }

    @Test("Commands without a selected agent stay disabled and cannot open a report")
    func disabledActions() async throws {
        try await withPaletteScene(scenario: .empty) { session, _, recorder in
            _ = try await dashboard(recorder)
            _ = try await openPalette(session, recorder)
            session.sendInput(Array("report".utf8))
            let unavailable = try await recorder.wait(description: "disabled report command") {
                $0.paletteQuery == "report" && $0.hasPaletteText("Open agent report")
            }
            #expect(unavailable.semantics.accessibilityNodes.contains {
                $0.role == .button && $0.label == "Open agent report" && !$0.isEnabled
            })
            session.send(.key(.return))
            session.send(.key(.backspace))
            _ = try await recorder.wait(after: unavailable.sequence, description: "disabled action leaves palette editing active") {
                $0.hasPalette && $0.paletteQuery == "repor"
            }
            session.send(.key(.escape))
            _ = try await recorder.wait(description: "empty dashboard preserved") {
                !$0.hasPalette && $0.hasPaletteText("No items yet.") && !$0.hasPaletteText("/ agent report")
            }
        }
    }

    @Test("Batched palette opening preserves type-ahead without triggering dashboard quit")
    func openingBatch() async throws {
        try await withPaletteScene { session, surface, recorder in
            _ = try await dashboard(recorder)
            session.sendInput([0x0B, 0x71])
            let seeded = try await recorder.wait(description: "Ctrl-K q carries type-ahead into the palette") {
                $0.hasPalette && $0.paletteQuery == "q"
            }
            session.sendInput(Array("uit".utf8))
            let edited = try await recorder.wait(after: seeded.sequence, description: "native editor extends initial query") {
                $0.paletteQuery == "quit"
            }
            surface.updateSurfaceSize(.init(width: 36, height: 18))
            session.requestSurfaceRefresh()
            let resized = try await recorder.wait(after: edited.sequence, description: "resize retains native edits after type-ahead") {
                $0.raster.size == CellSize(width: 36, height: 18) && $0.paletteQuery == "quit"
            }
            #expect(resized.focusedIdentity == edited.focusedIdentity)
            session.send(.key(.escape))
            _ = try await recorder.wait(description: "session remains usable after opening batch") {
                !$0.hasPalette && $0.hasPaletteText("/ agent workspace")
            }
        }
    }
}

private struct PaletteTestApp {
    let scenario: DashboardScenario

    nonisolated init() { scenario = .normal }
    nonisolated init(scenario: DashboardScenario) { self.scenario = scenario }
}

extension PaletteTestApp: App {
    var body: some Scene {
        WindowGroup(id: "palette-tests") { DashboardView(scenario: scenario, animates: false, paused: true) }
            .exitOnKeys([])
    }
}

@MainActor
private func withPaletteScene(
    scenario: DashboardScenario = .normal,
    perform: @MainActor (HostedSceneSession, HostedRasterSurface, HostedFrameRecorder) async throws -> Void
) async throws {
    let recorder = HostedFrameRecorder()
    let surface = HostedRasterSurface(surfaceSize: .init(width: 100, height: 30), appearance: .fallback,
                                      onFrame: { recorder.receive($0) })
    let session = try HostedSceneSession(for: PaletteTestApp(scenario: scenario), sceneID: "palette-tests", surface: surface)
    let run = Task { try await session.start() }
    defer { session.stop() }
    do {
        try await perform(session, surface, recorder)
        session.stop()
        #expect(try await run.value == .inputEnded)
    } catch {
        session.stop()
        _ = await run.result
        throw error
    }
}

@MainActor
private func dashboard(_ recorder: HostedFrameRecorder) async throws -> SemanticHostFrame {
    try await recorder.wait(description: "dashboard ready") {
        $0.hasPaletteText("/ agent workspace") && $0.focusedIdentity != nil
            && (!$0.focusesAnyTextField || $0.hasPaletteText("No items yet."))
    }
}

@MainActor
private func openPalette(_ session: HostedSceneSession, _ recorder: HostedFrameRecorder) async throws -> SemanticHostFrame {
    session.send(.key(.character("k"), modifiers: .ctrl))
    return try await recorder.wait(description: "palette has native filter focus") {
        $0.hasPalette && $0.focusesPaletteField
    }
}

private extension SemanticHostFrame {
    var focusesAnyTextField: Bool {
        semantics.accessibilityNodes.contains { $0.identity == focusedIdentity && $0.role == .textField }
    }
    func hasSelectedAgent(_ name: String) -> Bool {
        raster.lines.contains { $0.contains("›") && $0.contains(name) }
    }
    var hasPalette: Bool {
        semantics.accessibilityNodes.contains { $0.role == .textField && $0.label == "Filter commands…" }
    }
    var focusesPaletteField: Bool {
        semantics.accessibilityNodes.contains {
            $0.identity == focusedIdentity && $0.role == .textField && $0.label == "Filter commands…"
        }
    }
    var paletteQuery: String? {
        guard let field = semantics.accessibilityNodes.first(where: {
            $0.role == .textField && $0.label == "Filter commands…"
        }), case let .text(value) = field.control?.value else { return nil }
        return value
    }
    func hasPaletteText(_ text: String) -> Bool { raster.lines.contains { $0.contains(text) } }
}
