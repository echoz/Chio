@testable import ChioDashboard
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct AgentReportInteractionTests {
    @Test("Native report links dispatch locally, retain focus through theme and resize, and return to reading")
    func localLinkActivation() async throws {
        try await withReportScene { session, surface, recorder in
            let dashboard = try await filterDocs(session, recorder)
            let top = try await openReport(session, recorder)
            #expect(top.containsReportText("Links stay in this demo."))
            session.send(.key(.tab))
            let docs = try await recorder.wait(after: top.sequence, description: "Tab focuses the inline project docs link") {
                $0.isReport && $0.focusesReportInlineLink(0, label: "project docs")
            }
            session.send(.key(.return))
            let dispatched = try await recorder.wait(after: docs.sequence, description: "Enter reports the exact local documentation destination") {
                $0.isReport && $0.containsReportText("Link: Docs/Design.md")
            }
            #expect(dispatched.focusedIdentity == docs.focusedIdentity)
            session.send(.key(.tab))
            let outcome = try await recorder.wait(after: dispatched.sequence, description: "Tab focuses the next link in the same paragraph") {
                $0.isReport && $0.focusesReportInlineLink(1, label: "outcome")
            }
            #expect(outcome.focusedIdentity != docs.focusedIdentity)
            session.send(.key(.return))
            let fragment = try await recorder.wait(after: outcome.sequence, description: "Enter reports the fragment without navigating the report") {
                $0.isReport && $0.containsReportText("Link: #outcome")
            }
            #expect(fragment.focusedIdentity == outcome.focusedIdentity)
            #expect(fragment.containsReportText("project docs"))

            session.send(.key(.tab))
            let table = try await recorder.wait(after: fragment.sequence, description: "Tab after both links reaches the horizontal table scroll view") {
                $0.isReport && $0.hasReadingFocus && $0.focusedIdentity != top.focusedIdentity
            }
            session.send(.key(.tab, modifiers: .shift))
            let backToOutcome = try await recorder.wait(after: table.sequence, description: "Shift-Tab returns from the table to the outcome link") {
                $0.focusedIdentity == outcome.focusedIdentity
            }
            session.send(.key(.tab, modifiers: .shift))
            let backToDocs = try await recorder.wait(after: backToOutcome.sequence, description: "Shift-Tab returns to the project docs link") {
                $0.focusedIdentity == docs.focusedIdentity
            }
            session.send(.key(.tab, modifiers: .shift))
            let reading = try await recorder.wait(after: backToDocs.sequence, description: "Shift-Tab restores the exact vertical reading focus") {
                $0.isReport && $0.hasReadingFocus && $0.focusedIdentity == top.focusedIdentity
            }
            session.send(.key(.end))
            let bottom = try await recorder.wait(after: reading.sequence, description: "restored reading focus reaches the end and keeps destination feedback") {
                $0.isReport && $0.containsReportText("End of report.") && $0.containsReportText("Link: #outcome")
            }
            session.send(.key(.home))
            let home = try await recorder.wait(after: bottom.sequence, description: "Home returns to the top before refocusing a link") {
                $0.isReport && $0.containsReportText("Docs Agent") && $0.hasReadingFocus
            }
            session.send(.key(.tab))
            let focused = try await recorder.wait(after: home.sequence, description: "project docs link receives focus again") {
                $0.focusedIdentity == docs.focusedIdentity
            }
            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(after: focused.sequence, description: "Ctrl-T changes theme with a native link focused") {
                $0.isReport && $0.raster.cells != focused.raster.cells && $0.containsReportText("Link: #outcome")
            }
            #expect(themed.focusedIdentity == focused.focusedIdentity)
            surface.updateSurfaceSize(.init(width: 36, height: 18))
            session.requestSurfaceRefresh()
            let narrow = try await recorder.wait(after: themed.sequence, description: "compact report keeps focused link, persistent feedback, and navigation hints") {
                $0.isReport && $0.raster.size == CellSize(width: 36, height: 18)
            }
            #expect(narrow.focusedIdentity == focused.focusedIdentity)
            #expect(narrow.focusesReportInlineLink(0, label: "project docs"))
            #expect(narrow.containsReportText("project docs"))
            #expect(narrow.containsReportText("Link: #outcome"))
            #expect(narrow.hasReportChrome)
            #expect(narrow.containsReportText("tab focus"))
            #expect(narrow.containsReportText("enter link"))
            session.send(.key(.escape))
            let restored = try await recorder.wait(after: narrow.sequence, description: "Escape from a focused link restores filtered dashboard focus") {
                $0.isReportDashboard && $0.hasReportSelectedRow("Docs Agent")
            }
            #expect(restored.focusedIdentity == dashboard.focusedIdentity)
            let reopened = try await openReport(session, recorder)
            #expect(reopened.containsReportText("Links stay in this demo."))
            #expect(!reopened.containsReportText("Link: #outcome"))
        }
    }

    @Test("Completed reports scroll natively and keep their reading position through theme and resize")
    func readingThemeAndResize() async throws {
        try await withReportScene { session, surface, recorder in
            _ = try await filterDocs(session, recorder)
            let top = try await openReport(session, recorder)
            #expect(top.containsReportText("Docs Agent"))
            #expect(top.containsReportText("Complete"))
            session.send(.key(.arrowDown))
            let stepped = try await recorder.wait(after: top.sequence, description: "native Down scrolls the report") {
                $0.isReport && $0.raster.lines != top.raster.lines
            }
            #expect(stepped.focusedIdentity == top.focusedIdentity)
            session.send(.key(.end))
            let bottom = try await recorder.wait(after: stepped.sequence, description: "End reaches the completed outcome") {
                $0.isReport && $0.containsReportText("End of report.") && $0.containsReportText("All checks passed.")
            }
            #expect(!bottom.containsReportText("Docs Agent"))
            #expect(bottom.hasReportChrome)
            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(after: bottom.sequence, description: "theme changes while retaining the outcome") {
                $0.isReport && $0.raster.cells != bottom.raster.cells && $0.containsReportText("End of report.")
            }
            #expect(themed.raster.lines == bottom.raster.lines)
            #expect(themed.focusedIdentity == bottom.focusedIdentity)
            session.send(.key(.home))
            let home = try await recorder.wait(after: themed.sequence, description: "Home returns to the captured agent heading") {
                $0.isReport && $0.containsReportText("Docs Agent")
            }
            #expect(home.focusedIdentity == top.focusedIdentity)
            surface.updateSurfaceSize(.init(width: 36, height: 18))
            session.requestSurfaceRefresh()
            let resized = try await recorder.wait(after: home.sequence, description: "narrow resize retains the top and native reading focus") {
                $0.isReport && $0.raster.size == CellSize(width: 36, height: 18)
            }
            #expect(resized.containsReportText("Docs Agent"))
            #expect(resized.focusedIdentity == home.focusedIdentity)
            #expect(resized.hasReportChrome)
        }
    }

    @Test("Escape restores the filtered dashboard, selected agent, and exact native focus")
    func closeRestoresDashboard() async throws {
        try await withReportScene { session, _, recorder in
            let before = try await filterDocs(session, recorder)
            _ = try await openReport(session, recorder)
            session.send(.key(.escape))
            let restored = try await recorder.wait(after: before.sequence, description: "report closes to filtered Docs results") {
                $0.isReportDashboard && $0.hasReportControl(.textField, value: .text("docs"))
                    && $0.containsReportText("1 of 4 items") && $0.hasReportSelectedRow("Docs Agent")
            }
            #expect(restored.focusedIdentity == before.focusedIdentity)
            #expect(!restored.containsReportText("/ agent report"))
            session.send(.key(.return))
            let reopened = try await recorder.wait(after: restored.sequence, description: "restored results can reopen the same agent") {
                $0.isReport && $0.hasReadingFocus && $0.containsReportText("Docs Agent")
            }
            #expect(reopened.containsReportText("Complete"))
        }
    }

    @Test("A newly created idle agent can start and open its own running snapshot")
    func createdAgentReport() async throws {
        try await withReportScene { session, _, recorder in
            _ = try await waitForReportDashboard(recorder)
            session.send(.key(.character("n")))
            _ = try await recorder.wait(description: "creation has native Name focus") {
                $0.focusesReportControl(.textField, label: "Agent name")
            }
            session.sendInput(Array("Report Runner".utf8))
            _ = try await recorder.wait(description: "new agent name is entered") {
                $0.hasReportControl(.textField, label: "Agent name", value: .text("Report Runner"))
            }
            session.send(.key(.tab))
            _ = try await recorder.wait(description: "Tab reaches Role") { $0.focusesReportControl(.picker, label: "Role") }
            session.send(.key(.tab))
            _ = try await recorder.wait(description: "Tab reaches Start immediately") {
                $0.focusesReportControl(.toggle, label: "Start immediately")
            }
            session.send(.key(.space))
            _ = try await recorder.wait(description: "creation starts idle") {
                $0.hasReportControl(.toggle, label: "Start immediately", value: .boolean(false))
            }
            session.send(.key(.character("s"), modifiers: .ctrl))
            let created = try await recorder.wait(description: "new idle agent is selected in dashboard results") {
                $0.isReportDashboard && $0.containsReportText("5 of 5 items")
                    && $0.hasReportSelectedRow("Report Runner") && $0.containsReportText("○ Idle")
            }
            session.send(.key(.character("r")))
            let running = try await recorder.wait(after: created.sequence, description: "selected new agent starts at zero percent") {
                $0.isReportDashboard && $0.hasReportSelectedRow("Report Runner") && $0.containsReportText("0%")
            }
            session.send(.key(.return))
            let report = try await recorder.wait(after: running.sequence, description: "new agent's running snapshot opens") {
                $0.isReport && $0.hasReadingFocus && $0.containsReportText("Report Runner")
            }
            #expect(report.containsReportText("Running"))
            #expect(!report.containsReportText("Build Agent"))
            session.send(.key(.end))
            let outcome = try await recorder.wait(after: report.sequence, description: "new run reports its captured zero percent") {
                $0.isReport && $0.containsReportText("End of report.")
            }
            #expect(outcome.containsReportText("0% complete"))
        }
    }

    @Test("Enter and q in one terminal read open a report without quitting during the cover handoff")
    func batchedOpenDoesNotQuit() async throws {
        try await withReportScene { session, _, recorder in
            let before = try await waitForReportDashboard(recorder)
            session.sendInput(Array("\rq".utf8))
            let opened = try await recorder.wait(after: before.sequence, description: "batched Enter-q opens the selected report") {
                $0.isReport && $0.hasReadingFocus && $0.containsReportText("Build Agent")
            }
            session.send(.key(.escape))
            let returned = try await recorder.wait(after: opened.sequence, description: "session still accepts Escape after batched q") {
                $0.isReportDashboard && $0.hasReportSelectedRow("Build Agent")
            }
            #expect(returned.focusedIdentity == before.focusedIdentity)
        }
    }
}

private struct ReportTestApp {
    nonisolated init() {}
}

extension ReportTestApp: App {
    var body: some Scene {
        WindowGroup(id: "report-tests") { DashboardView(animates: false, paused: true) }
            .exitOnKeys([])
    }
}

@MainActor
private func withReportScene(
    perform: @MainActor (HostedSceneSession, HostedRasterSurface, HostedFrameRecorder) async throws -> Void
) async throws {
    let recorder = HostedFrameRecorder()
    let surface = HostedRasterSurface(surfaceSize: .init(width: 100, height: 30), appearance: .fallback,
                                      onFrame: { recorder.receive($0) })
    let session = try HostedSceneSession(for: ReportTestApp(), sceneID: "report-tests", surface: surface)
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
private func waitForReportDashboard(_ recorder: HostedFrameRecorder) async throws -> SemanticHostFrame {
    try await recorder.wait(description: "dashboard has native results focus") {
        $0.isReportDashboard && $0.focusedIdentity != nil && !$0.focusesReportControl(.textField)
    }
}

@MainActor
private func filterDocs(_ session: HostedSceneSession, _ recorder: HostedFrameRecorder) async throws -> SemanticHostFrame {
    _ = try await waitForReportDashboard(recorder)
    session.sendInput(Array("/docs\r".utf8))
    return try await recorder.wait(description: "filtered Docs agent has results focus") {
        $0.isReportDashboard && $0.hasReportControl(.textField, value: .text("docs"))
            && !$0.focusesReportControl(.textField) && $0.hasReportSelectedRow("Docs Agent")
            && $0.containsReportText("1 of 4 items")
    }
}

@MainActor
private func openReport(_ session: HostedSceneSession, _ recorder: HostedFrameRecorder) async throws -> SemanticHostFrame {
    session.send(.key(.return))
    return try await recorder.wait(description: "native report scroll view receives reading focus") {
        $0.isReport && $0.hasReadingFocus
    }
}

private extension SemanticHostFrame {
    var isReport: Bool { containsReportText("/ agent report") }
    var isReportDashboard: Bool { containsReportText("/ agent workspace") && !isReport && !containsReportText("/ create agent") }
    var hasReadingFocus: Bool { focusesReportControl(.scrollView) || focusesReportControl(.scrollViewWithIndicators) }
    var hasReportChrome: Bool {
        isReport && containsReportText("snapshot") && containsReportText("↑↓ scroll")
            && containsReportText("home/end jump") && containsReportText("esc back") && containsReportText("^T theme")
    }
    func containsReportText(_ text: String) -> Bool { raster.lines.contains { $0.contains(text) } }
    func hasReportSelectedRow(_ name: String) -> Bool {
        raster.lines.contains { $0.contains(name) && $0.contains("›") }
    }
    func hasReportControl(_ role: AccessibilityRole, label: String? = nil, value: AccessibilityValue? = nil) -> Bool {
        semantics.accessibilityNodes.contains {
            $0.role == role && (label == nil || $0.label == label) && (value == nil || $0.control?.value == value)
        }
    }
    func focusesReportControl(_ role: AccessibilityRole, label: String? = nil) -> Bool {
        guard let focusedIdentity else { return false }
        return semantics.accessibilityNodes.contains {
            $0.identity == focusedIdentity && $0.role == role && (label == nil || $0.label == label)
        }
    }
    func focusesReportInlineLink(_ index: Int, label: String) -> Bool {
        guard let focusedIdentity,
              focusedIdentity.description.contains("InlineLink[\(index)]") else { return false }
        return containsReportText(label) && semantics.focusRegions.contains {
            $0.identity == focusedIdentity && $0.focusInteractions == .activate
        }
    }
}
