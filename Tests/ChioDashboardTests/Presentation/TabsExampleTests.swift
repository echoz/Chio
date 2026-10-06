@testable import ChioDashboard
import Chio
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct TabsExampleTests {
    @Test("Workspace tabs retain essential content and hints across sizes and themes",
          arguments: [CellSize(width: 100, height: 30), CellSize(width: 50, height: 30),
                      CellSize(width: 36, height: 18)], ExampleTheme.allCases)
    func initialLayout(size: CellSize, appearance: ExampleTheme) {
        let rendered = DefaultRenderer().render(
            TabsExampleView(theme: appearance).environment(\.terminalSize, size),
            proposal: .init(width: size.width, height: size.height), frameInstant: .zero
        )
        let surface = rendered.rasterSurface
        let text = surface.lines.joined(separator: "\n")
        #expect(surface.size == size)
        #expect(text.contains("/ workspace tabs"))
        #expect(text.contains("Overview") && text.contains("Agents") && text.contains("4"))
        #expect(text.contains("Workspace overview") && text.contains("Demo runs: 0"))
        #expect(text.contains("Run demo"))
        #expect(text.contains("tab focus") && text.contains("^T theme") && text.contains("^Q quit"))
        #expect(rendered.semanticSnapshot.accessibilityNodes.contains { $0.role == .tabView })
        #expect(rendered.semanticSnapshot.accessibilityNodes.contains { $0.role == .button && $0.label == "Run demo" })
        if size.width == 36 { #expect(text.contains("More ▾")) }
        let theme = appearance.theme
        #expect(surface.cells.flatMap { $0 }.contains {
            $0.character == "W" && $0.style?.foregroundColor == theme.colors.heading
        })
    }

    @Test("Initial native strip focus separates highlighted tabs from committed content")
    func highlightAndCommit() async throws {
        try await withTabsExample { session, _, recorder in
            let initial = try await recorder.wait(description: "Overview starts with native tab strip focus") {
                $0.workspaceStripFocused && $0.workspaceContains("Demo runs: 0")
            }
            session.send(.key(.arrowRight))
            let highlighted = try await recorder.wait(after: initial.sequence, description: "Right highlights Agents while Overview stays active") {
                $0.workspaceStripFocused && $0.raster.cells != initial.raster.cells
            }
            #expect(highlighted.workspaceContains("Workspace overview"))
            #expect(!highlighted.workspaceContains("Agent directory"))
            session.send(.key(.return))
            _ = try await recorder.wait(after: highlighted.sequence, description: "Return commits the highlighted Agents tab") {
                $0.workspaceContains("Agent directory") && $0.workspaceContains("Build Agent")
                    && $0.workspaceAgentResultsReady
            }
            try await selectWorkspaceTab(0, heading: "Workspace overview", session: session, recorder: recorder)
            session.send(.key(.end))
            let last = try await recorder.wait(description: "End highlights Settings with Overview still active") {
                $0.workspaceStripFocused && $0.workspaceContains("Demo runs: 0")
            }
            session.send(.key(.space))
            _ = try await recorder.wait(after: last.sequence, description: "Space commits the final Settings tab") {
                $0.workspaceContains("Workspace settings") && $0.workspaceContains("Quiet mode: off")
            }
        }
    }

    @Test("Native Tab and Shift-Tab reach page controls and Overview state survives dormancy")
    func overviewStateAndFocusNavigation() async throws {
        try await withTabsExample { session, _, recorder in
            _ = try await recorder.wait(description: "Overview strip ready") { $0.workspaceStripFocused }
            session.send(.key(.tab))
            let button = try await recorder.wait(description: "Tab reaches the native Run demo button") {
                $0.workspaceFocused(.button, label: "Run demo")
            }
            #expect(button.workspaceContains("F6 tabs"))
            session.send(.key(.return))
            _ = try await recorder.wait(description: "native button activation increments the local counter") {
                $0.workspaceContains("Demo runs: 1")
            }
            session.send(.key(.tab, modifiers: .shift))
            _ = try await recorder.wait(description: "Shift-Tab returns from Run demo to the strip") { $0.workspaceStripFocused }
            session.send(.key(.tab))
            _ = try await recorder.wait(description: "Tab can revisit the page button") { $0.workspaceFocused(.button, label: "Run demo") }
            try await selectWorkspaceTab(2, heading: "Scratch notes", session: session, recorder: recorder)
            try await selectWorkspaceTab(0, heading: "Workspace overview", session: session, recorder: recorder)
            _ = try await recorder.wait(description: "Overview counter restored from dormant content") {
                $0.workspaceContains("Demo runs: 1")
            }
            session.send(.key(.tab))
            _ = try await recorder.wait(description: "restored Overview button remains native") { $0.workspaceFocused(.button, label: "Run demo") }
            session.send(.key(.space))
            _ = try await recorder.wait(description: "restored button continues from the retained counter") { $0.workspaceContains("Demo runs: 2") }
        }
    }

    @Test("Notes use native editing and F6 while drafts, selection and focus survive theme and resize")
    func notesDraftAndGeometry() async throws {
        try await withTabsExample { session, surface, recorder in
            _ = try await recorder.wait(description: "initial workspace strip ready") { $0.workspaceStripFocused }
            try await selectWorkspaceTab(2, heading: "Scratch notes", session: session, recorder: recorder)
            session.send(.key(.tab))
            _ = try await recorder.wait(description: "Tab reaches the native notes editor") { $0.workspaceFocused(.textEditor) }
            session.sendInput(Array("abc".utf8))
            _ = try await recorder.wait(description: "notes draft typed") { $0.workspaceNotes("abc") }
            session.send([.key(.arrowLeft), .key(.backspace), .key(.character("X"))])
            let edited = try await recorder.wait(description: "native caret movement edits notes without changing tabs") {
                $0.workspaceFocused(.textEditor) && $0.workspaceNotes("aXc")
            }
            #expect(edited.workspaceContains("Scratch notes") && edited.workspaceContains("Characters: 3"))
            session.send(.key(.tab, modifiers: .shift))
            _ = try await recorder.wait(description: "Shift-Tab leaves the editor for the native strip") { $0.workspaceStripFocused }
            session.send(.key(.tab))
            let beforeTheme = try await recorder.wait(description: "Tab returns to the same notes editor") {
                $0.workspaceFocused(.textEditor) && $0.workspaceNotes("aXc")
            }
            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(after: beforeTheme.sequence, description: "theme updates paint while preserving Notes and its editor") {
                $0.raster.cells != beforeTheme.raster.cells && $0.workspaceFocused(.textEditor) && $0.workspaceNotes("aXc")
            }
            #expect(themed.focusedIdentity == edited.focusedIdentity)
            surface.updateSurfaceSize(.init(width: 36, height: 18))
            session.requestSurfaceRefresh()
            let compact = try await recorder.wait(after: themed.sequence, description: "compact Notes preserves the draft and native editor focus") {
                $0.raster.size == CellSize(width: 36, height: 18) && $0.workspaceFocused(.textEditor)
                    && $0.workspaceNotes("aXc")
            }
            #expect(compact.focusedIdentity == edited.focusedIdentity)
            #expect(compact.workspaceContains("Scratch notes") && compact.workspaceContains("Characters: 3"))
            #expect(compact.workspaceContains("F6 tabs") && compact.workspaceContains("^Q quit"))
            session.send(.key(.functionKey(6)))
            _ = try await recorder.wait(after: compact.sequence, description: "F6 targets the native tab strip from the compact editor") {
                $0.workspaceStripFocused && $0.workspaceNotes("aXc")
            }
            surface.updateSurfaceSize(.init(width: 100, height: 30))
            session.requestSurfaceRefresh()
            _ = try await recorder.wait(description: "wide Notes returns without losing the draft") {
                $0.raster.size == CellSize(width: 100, height: 30) && $0.workspaceNotes("aXc")
            }
            try await selectWorkspaceTab(0, heading: "Workspace overview", session: session, recorder: recorder)
            try await selectWorkspaceTab(2, heading: "Scratch notes", session: session, recorder: recorder)
            _ = try await recorder.wait(description: "Notes draft survives an Overview round trip") { $0.workspaceNotes("aXc") }
            session.send(.key(.tab))
            _ = try await recorder.wait(description: "restored Notes is editable") { $0.workspaceFocused(.textEditor) }
            session.send(.key(.end))
            session.send(.key(.character("!")))
            _ = try await recorder.wait(description: "retained draft accepts native editing after restoration") { $0.workspaceNotes("aXc!") }
        }
    }

    @Test("Agent search punctuation remains text and F6 reaches the strip from native search")
    func agentsNativeSearch() async throws {
        try await withTabsExample { session, _, recorder in
            _ = try await recorder.wait(description: "workspace strip ready") { $0.workspaceStripFocused }
            try await selectWorkspaceTab(1, heading: "Agent directory", session: session, recorder: recorder)
            _ = try await focusWorkspaceStrip(session: session, recorder: recorder)
            session.send(.key(.tab))
            _ = try await recorder.wait(description: "native Tab enters agent search") { $0.workspaceFocused(.textField) }
            session.sendInput(Array("/?".utf8))
            let editing = try await recorder.wait(description: "ordinary punctuation reaches the native agent query") {
                $0.workspaceQuery("/?") && $0.workspaceFocused(.textField)
            }
            #expect(editing.workspaceContains("Agent directory"))
            session.send(.key(.functionKey(6)))
            _ = try await recorder.wait(after: editing.sequence, description: "F6 leaves the agent editor without changing its query") {
                $0.workspaceStripFocused && $0.workspaceQuery("/?")
            }
            try await selectWorkspaceTab(0, heading: "Workspace overview", session: session, recorder: recorder)
            try await selectWorkspaceTab(1, heading: "Agent directory", session: session, recorder: recorder)
            _ = try await recorder.wait(description: "native dormant agent search retains its query") { $0.workspaceQuery("/?") }
        }
    }

    @Test("Settings state and native Activity scrolling remain usable after tab switches")
    func settingsAndActivity() async throws {
        try await withTabsExample { session, _, recorder in
            _ = try await recorder.wait(description: "workspace strip ready") { $0.workspaceStripFocused }
            try await selectWorkspaceTab(4, heading: "Workspace settings", session: session, recorder: recorder)
            session.send(.key(.tab))
            _ = try await recorder.wait(description: "Tab reaches the native Quiet mode toggle") { $0.workspaceFocused(.toggle) }
            session.send(.key(.space))
            _ = try await recorder.wait(description: "native toggle updates local setting") { $0.workspaceContains("Quiet mode: on") }
            try await selectWorkspaceTab(3, heading: "Activity log", session: session, recorder: recorder)
            session.send(.key(.tab))
            _ = try await recorder.wait(description: "Tab reaches the native Activity viewport") {
                $0.workspaceFocused(.scrollView) || $0.workspaceFocused(.scrollViewWithIndicators)
            }
            session.send(.key(.end))
            _ = try await recorder.wait(description: "native End reveals the final Activity event") { $0.workspaceContains("Event 40 · Workspace activity") }
            session.send(.key(.home))
            _ = try await recorder.wait(description: "native Home returns to the first Activity event") { $0.workspaceContains("Event 01 · Workspace activity") }
            try await selectWorkspaceTab(4, heading: "Workspace settings", session: session, recorder: recorder)
            _ = try await recorder.wait(description: "Quiet mode survives dormant Settings content") { $0.workspaceContains("Quiet mode: on") }
        }
    }

    @Test("Compact More opens, cancels, selects either overflow edge and reopens", arguments: [false, true])
    func compactOverflow(selectLast: Bool) async throws {
        try await withTabsExample(size: .init(width: 36, height: 18)) { session, _, recorder in
            let initial = try await recorder.wait(description: "compact workspace starts with a collapsed More trigger") {
                $0.workspaceStripFocused && $0.workspaceContains("More ▾") && $0.workspaceContains("Demo runs: 0")
                    && $0.workspaceContains("↓ more")
            }
            #expect(initial.workspaceContains("↓ more"))
            session.send(.key(.end))
            session.send(.key(.arrowDown))
            let opened = try await recorder.wait(after: initial.sequence, description: "native Down opens More with all overflow options visible") {
                $0.workspaceContains("More ▴") && $0.workspaceContains("Notes")
                    && $0.workspaceContains("Activity") && $0.workspaceContains("Settings")
            }
            #expect(opened.workspaceContains("Demo runs: 0"))
            session.send(.key(.escape))
            let cancelled = try await recorder.wait(after: opened.sequence, description: "Escape collapses More and retains Overview") {
                $0.workspaceStripFocused && $0.workspaceContains("More ▾") && $0.workspaceContains("Demo runs: 0")
            }
            session.send(.key(.arrowDown))
            let reopened = try await recorder.wait(after: cancelled.sequence, description: "More reopens after native cancellation") {
                $0.workspaceContains("More ▴") && $0.workspaceContains("Settings")
            }
            // Navigation uses the freshly rendered expanded presentation. The
            // opening key and a second Down in one batch are an upstream gap.
            if !selectLast {
                session.send([.key(.arrowUp), .key(.arrowUp)])
                _ = try await recorder.wait(after: reopened.sequence, description: "Up highlights the first overflow option without committing") {
                    $0.workspaceContains("More ▴") && $0.raster.cells != reopened.raster.cells
                }
            }
            session.send(.key(.return))
            let selected = try await recorder.wait(after: reopened.sequence, description: "Return commits the chosen native overflow option") {
                $0.workspaceContains("More ▾")
                    && $0.workspaceContains(selectLast ? "Quiet mode: off" : "Scratch notes")
            }
            #expect(!selected.workspaceContains("Demo runs: 0"))
            session.send(.key(.functionKey(6)))
            _ = try await recorder.wait(description: "chosen compact page can return focus to the strip") { $0.workspaceStripFocused }
            session.send(.key(.arrowDown))
            let again = try await recorder.wait(after: selected.sequence, description: "More reopens after native overflow activation") {
                $0.workspaceContains("More ▴") && $0.workspaceContains("Activity") && $0.workspaceContains("Settings")
            }
            session.send(.key(.escape))
            _ = try await recorder.wait(after: again.sequence, description: "cancelled reopened menu preserves the selected page") {
                $0.workspaceContains("More ▾")
                    && $0.workspaceContains(selectLast ? "Quiet mode: off" : "Scratch notes")
            }
        }
    }

    @Test("Public pointer input selects visible tabs and native More menu rows")
    func pointerTabSelection() async throws {
        try await withTabsExample { session, surface, recorder in
            let initial = try await recorder.wait(description: "wide tab labels are ready for pointer input") {
                $0.workspaceStripFocused && $0.workspaceContains("Overview") && $0.workspaceContains("Notes")
            }
            let notesPoint = try #require(initial.workspaceLabelPoint("Notes"))
            clickWorkspacePoint(notesPoint, session: session)
            let notes = try await recorder.wait(after: initial.sequence, description: "clicking the visible Notes label selects its page") {
                $0.workspaceContains("Scratch notes") && $0.workspaceNotes("")
            }
            surface.updateSurfaceSize(.init(width: 36, height: 18))
            session.requestSurfaceRefresh()
            let compact = try await recorder.wait(after: notes.sequence, description: "compact More trigger is ready for pointer input") {
                $0.raster.size == CellSize(width: 36, height: 18) && $0.workspaceContains("More ▾")
            }
            let morePoint = try #require(compact.workspaceLabelPoint("More ▾"))
            clickWorkspacePoint(morePoint, session: session)
            let menu = try await recorder.wait(after: compact.sequence, description: "clicking More opens the native overflow menu") {
                $0.workspaceContains("More ▴") && $0.workspaceContains("Settings")
            }
            let settingsPoint = try #require(menu.workspaceLabelPoint("Settings"))
            clickWorkspacePoint(settingsPoint, session: session)
            _ = try await recorder.wait(after: menu.sequence, description: "clicking the overflow Settings row selects its page and collapses More") {
                $0.workspaceContains("More ▾") && $0.workspaceContains("Workspace settings")
                    && $0.workspaceContains("Quiet mode: off")
            }
        }
    }
}

@MainActor
private func clickWorkspacePoint(_ point: Point, session: HostedSceneSession) {
    session.send([
        .mouse(.init(kind: .down(.primary), location: point)),
        .mouse(.init(kind: .up(.primary), location: point)),
    ])
}

@MainActor
private func selectWorkspaceTab(
    _ index: Int, heading: String, session: HostedSceneSession, recorder: HostedFrameRecorder
) async throws {
    let focused = try await focusWorkspaceStrip(session: session, recorder: recorder)
    let navigation = [InputEvent.key(.home)] + Array(repeating: InputEvent.key(.arrowRight), count: index)
    session.send(navigation + [.key(.return)])
    _ = try await recorder.wait(after: focused.sequence, description: "native strip commits \(heading) and its initial focus settles") {
        guard $0.workspaceContains(heading) else { return false }
        // SearchableList requests results focus on appearance. Its first
        // committed content frame can still carry the departing strip focus.
        // A retained no-match query has no result target to await.
        return index != 1 || !$0.workspaceQuery("") || $0.workspaceAgentResultsReady
    }
}

@MainActor
private func focusWorkspaceStrip(
    session: HostedSceneSession, recorder: HostedFrameRecorder
) async throws -> SemanticHostFrame {
    let before = try await recorder.wait(description: "current workspace frame before F6") { _ in true }
    session.send(.key(.functionKey(6)))
    session.requestSurfaceRefresh()
    return try await recorder.wait(after: before.sequence, description: "F6 focuses the native strip and synchronizes its navigation hints") {
        $0.workspaceStripFocused && $0.workspaceContains("←→ choose")
            && $0.workspaceContains("↵ open") && $0.workspaceContains("↓ more")
    }
}

private struct TabsExampleTestApp {
    nonisolated init() {}
}

extension TabsExampleTestApp: App {
    var body: some Scene {
        WindowGroup(id: "tabs-example-tests") { TabsExampleView() }.exitOnKeys([])
    }
}

@MainActor
private func withTabsExample(
    size: CellSize = .init(width: 100, height: 30),
    perform: @MainActor (HostedSceneSession, HostedRasterSurface, HostedFrameRecorder) async throws -> Void
) async throws {
    let recorder = HostedFrameRecorder()
    let surface = HostedRasterSurface(surfaceSize: size, appearance: .fallback, onFrame: { recorder.receive($0) })
    let session = try HostedSceneSession(for: TabsExampleTestApp(), sceneID: "tabs-example-tests", surface: surface)
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

private extension SemanticHostFrame {
    func workspaceContains(_ text: String) -> Bool { raster.lines.contains { $0.contains(text) } }
    var workspaceStripFocused: Bool { workspaceFocused(.tabView) }
    var workspaceAgentResultsReady: Bool {
        workspaceContains("Agent directory") && workspaceContains("F6 tabs")
            && !workspaceStripFocused && !workspaceFocused(.textField)
            && semantics.focusRegions.contains { $0.identity == focusedIdentity }
    }
    func workspaceFocused(_ role: AccessibilityRole, label: String? = nil) -> Bool {
        semantics.accessibilityNodes.contains {
            $0.identity == focusedIdentity && $0.role == role && (label == nil || $0.label == label)
        }
    }
    func workspaceNotes(_ value: String) -> Bool {
        semantics.accessibilityNodes.contains { $0.role == .textEditor && $0.control?.value == .text(value) }
    }
    func workspaceQuery(_ value: String) -> Bool {
        semantics.accessibilityNodes.contains { $0.role == .textField && $0.control?.value == .text(value) }
    }
    func workspaceLabelPoint(_ label: String) -> Point? {
        for (row, line) in raster.lines.enumerated() {
            guard let range = line.range(of: label) else { continue }
            let column = line.distance(from: line.startIndex, to: range.lowerBound)
            return Point(x: Double(column), y: Double(row))
        }
        return nil
    }
}
