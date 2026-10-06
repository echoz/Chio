@testable import ChioDashboard
import Chio
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct HelpExampleTests {
    @Test("Slash followed by a question mark in one read edits search without opening help")
    func batchedSearchQuestionMark() async throws {
        try await withHelpExample { session, _, recorder in
            let ready = try await helpResultsReady(recorder)
            session.sendInput(Array("/?".utf8))
            let editing = try await recorder.wait(after: ready.sequence, description: "question mark reaches native search") {
                $0.helpEditorFocused && $0.helpQuery("?") && $0.helpContains("F1 help")
            }
            #expect(!editing.helpIsPresented)
            #expect(editing.helpContains("Runs: 0"))
            #expect(editing.helpContains("F1 help"))
            session.send(.key(.functionKey(1)))
            let opened = try await recorder.wait(after: editing.sequence, description: "F1 opens all shortcuts for punctuation query") {
                $0.helpIsPresented && $0.helpContains("All shortcuts")
            }
            session.send(.key(.escape))
            let restored = try await recorder.wait(after: opened.sequence, description: "punctuation query returns to native editor") {
                !$0.helpIsPresented && $0.helpEditorFocused && $0.helpQuery("?")
            }
            #expect(restored.focusedIdentity == editing.focusedIdentity)
        }
    }

    @Test("Browse help restores the filtered selection and exact focus and can reopen with Shift-question mark")
    func resultHelpRestoration() async throws {
        try await withHelpExample { session, _, recorder in
            let before = try await filterHelpReview(session, recorder)
            session.send(.key(.character("?")))
            let opened = try await recorder.wait(after: before.sequence, description: "Browse shortcuts open from results") {
                $0.helpIsPresented && $0.helpContains("Browse")
            }
            session.send(.key(.escape))
            let restored = try await recorder.wait(after: opened.sequence, description: "filtered Review results regain native focus") {
                !$0.helpIsPresented && $0.helpResultsFocused && $0.helpQuery("Review")
                    && $0.helpSelectedRow("Review Agent") && $0.helpContains("1 of 4 items")
            }
            #expect(restored.focusedIdentity == before.focusedIdentity)
            #expect(restored.helpContains("Runs: 0"))
            session.send(.key(.character("?"), modifiers: .shift))
            let reopened = try await recorder.wait(after: restored.sequence, description: "Shift-question mark reopens Browse help") {
                $0.helpIsPresented && $0.helpContains("Browse")
            }
            session.send(.key(.escape))
            _ = try await recorder.wait(after: reopened.sequence, description: "reopened help restores Review results") {
                !$0.helpIsPresented && $0.focusedIdentity == before.focusedIdentity && $0.helpQuery("Review")
            }
            session.send(.key(.return))
            let activated = try await recorder.wait(description: "restored selected Review can activate natively") {
                $0.helpContains("Runs: 1")
            }
            #expect(activated.helpSelectedRow("Review Agent"))
        }
    }

    @Test("F1 opens all shortcuts without changing native editor focus or query after dismissal")
    func editorHelpRestoration() async throws {
        try await withHelpExample { session, _, recorder in
            _ = try await helpResultsReady(recorder)
            session.sendInput(Array("/Review".utf8))
            let editing = try await recorder.wait(description: "Review is current in native search") {
                $0.helpEditorFocused && $0.helpQuery("Review") && $0.helpSelectedRow("Review Agent")
            }
            session.send(.key(.functionKey(1)))
            let opened = try await recorder.wait(after: editing.sequence, description: "F1 opens the full shortcut reference") {
                $0.helpIsPresented && $0.helpContains("All shortcuts")
            }
            session.send(.key(.escape))
            let restored = try await recorder.wait(after: opened.sequence, description: "help restores the edited query and exact editor") {
                !$0.helpIsPresented && $0.helpEditorFocused && $0.helpQuery("Review")
                    && $0.helpSelectedRow("Review Agent")
            }
            #expect(restored.focusedIdentity == editing.focusedIdentity)
            session.send(.key(.character("?")))
            let appended = try await recorder.wait(after: restored.sequence, description: "question mark remains ordinary editor text") {
                $0.helpEditorFocused && $0.helpQuery("Review?")
            }
            #expect(!appended.helpIsPresented)
        }
    }

    @Test("F1 in a search focus transition opens a stable full reference and preserves the query",
          arguments: [false, true])
    func batchedSearchTransitionF1(returnToResults: Bool) async throws {
        try await withHelpExample { session, _, recorder in
            let ready = try await helpResultsReady(recorder)
            let before: SemanticHostFrame
            if returnToResults {
                session.sendInput(Array("/Review".utf8))
                before = try await recorder.wait(after: ready.sequence, description: "Review editor is ready before Return-F1") {
                    $0.helpEditorFocused && $0.helpQuery("Review") && $0.helpContains("F1 help")
                }
                session.send([.key(.return), .key(.functionKey(1))])
            } else {
                before = ready
                let editingEvents = "/Review".map { InputEvent.key(.character($0)) }
                session.send(editingEvents + [.key(.functionKey(1))])
            }
            let opened = try await recorder.wait(after: before.sequence, description: "batched F1 opens all shortcuts during native focus handoff") {
                $0.helpIsPresented && $0.helpContains("All shortcuts") && $0.helpContains("Browse")
            }
            session.send(.key(.escape))
            var restored = try await recorder.wait(after: opened.sequence, description: "batched F1 keeps Review query and selected result") {
                !$0.helpIsPresented && $0.helpQuery("Review") && $0.helpSelectedRow("Review Agent")
                    && ($0.helpEditorFocused || $0.helpResultsFocused)
            }
            #expect(restored.helpContains("Runs: 0"))
            // The original target is still in a native focus handoff at opening.
            // Check retained query/selection and usable controls rather than an
            // identity for a control that has not yet received a rendered frame.
            if restored.helpEditorFocused {
                session.send(.key(.return))
                restored = try await recorder.wait(after: restored.sequence, description: "restored native editor can return to Review results") {
                    $0.helpResultsFocused && $0.helpQuery("Review") && $0.helpSelectedRow("Review Agent")
                }
            }
            session.send(.key(.return))
            _ = try await recorder.wait(after: restored.sequence, description: "restored native result remains activatable") {
                $0.helpContains("Runs: 1") && $0.helpSelectedRow("Review Agent")
            }
        }
    }

    @Test("Pending and presented help block Run, and a batched Escape preserves the filter")
    func batchedHelpGuardsBackgroundActions() async throws {
        try await withHelpExample { session, _, recorder in
            let before = try await filterHelpReview(session, recorder)
            session.sendInput([63, 18]) // Question mark and Ctrl-R in one terminal read.
            let opened = try await recorder.wait(after: before.sequence, description: "help opens before pending Run can dispatch") {
                $0.helpIsPresented && $0.helpContains("Browse")
            }
            session.sendInput([18, 27]) // Ctrl-R while modal, then native Escape.
            let restored = try await recorder.wait(after: opened.sequence, description: "modal Run is inert and Escape restores results") {
                !$0.helpIsPresented && $0.helpResultsFocused && $0.helpQuery("Review")
                    && $0.helpContains("Runs: 0") && $0.helpSelectedRow("Review Agent")
            }
            #expect(restored.focusedIdentity == before.focusedIdentity)
            session.sendInput([63, 27])
            let cancelled = try await recorder.wait(after: restored.sequence, description: "opening-batch Escape keeps the current filter") {
                !$0.helpIsPresented && $0.helpQuery("Review") && $0.helpResultsFocused
                    && $0.helpContains("1 of 4 items")
            }
            #expect(cancelled.focusedIdentity == before.focusedIdentity)
            #expect(cancelled.helpSelectedRow("Review Agent"))
            #expect(cancelled.helpContains("Runs: 0"))
            session.send(.key(.character("r"), modifiers: .ctrl))
            _ = try await recorder.wait(after: cancelled.sequence, description: "Run works again after cancellation") {
                $0.helpContains("Runs: 1")
            }
        }
    }

    @Test("Native Help and Run buttons activate and native Close restores the Help button")
    func nativeActionButtons() async throws {
        try await withHelpExample { session, _, recorder in
            let ready = try await helpResultsReady(recorder)
            let runButton = try await focusHelpControl(from: ready, session: session, recorder: recorder) {
                $0.helpButtonFocused("Run")
            }
            session.send(.key(.return))
            let ran = try await recorder.wait(after: runButton.sequence, description: "native Run button updates local count") {
                $0.helpContains("Runs: 1") && $0.helpButtonFocused("Run")
            }
            let trigger = try await focusHelpControl(from: ran, session: session, recorder: recorder) {
                $0.helpButtonFocused("Help")
            }
            session.send(.key(.return))
            let opened = try await recorder.wait(after: trigger.sequence, description: "native Help opens action shortcuts") {
                $0.helpIsPresented && $0.helpContains("Actions")
            }
            _ = try await focusHelpControl(from: opened, session: session, recorder: recorder) {
                $0.helpButtonFocused("Close")
            }
            session.send(.key(.return))
            let restored = try await recorder.wait(description: "native Close restores the Help trigger") {
                !$0.helpIsPresented && $0.helpButtonFocused("Help")
            }
            #expect(restored.focusedIdentity == trigger.focusedIdentity)
            #expect(restored.helpContains("Runs: 1"))
            session.send(.key(.character("?")))
            let reopened = try await recorder.wait(after: restored.sequence, description: "question mark opens from focused action button") {
                $0.helpIsPresented && $0.helpContains("Actions")
            }
            session.send(.key(.escape))
            _ = try await recorder.wait(after: reopened.sequence, description: "Escape restores action-button focus") {
                !$0.helpIsPresented && $0.focusedIdentity == trigger.focusedIdentity
            }
        }
    }

    @Test("Unavailable Run is omitted from help and cannot activate with an empty result set")
    func unavailableRun() async throws {
        try await withHelpExample { session, _, recorder in
            _ = try await helpResultsReady(recorder)
            session.sendInput(Array("/zzzzzz".utf8))
            let empty = try await recorder.wait(description: "empty results disable the native Run action") {
                $0.helpQuery("zzzzzz") && $0.helpEditorFocused
                    && $0.semantics.accessibilityNodes.contains { $0.role == .button && $0.label == "Run" && !$0.isEnabled }
            }
            session.send(.key(.functionKey(1)))
            let opened = try await recorder.wait(after: empty.sequence, description: "full shortcut reference opens for no results") {
                $0.helpIsPresented && $0.helpContains("All shortcuts")
            }
            let viewport = try await focusHelpControl(from: opened, session: session, recorder: recorder) {
                $0.helpViewportFocused
            }
            session.send(.key(.end))
            let bottom = try await recorder.wait(after: viewport.sequence, description: "native End exposes available application shortcuts") {
                $0.helpIsPresented && $0.helpContains("Application") && $0.helpContains("Close help")
            }
            #expect(bottom.helpContains("^T theme"))
            #expect(bottom.helpContains("^Q quit"))
            #expect(!bottom.helpContains("^R run"))
            session.send(.key(.escape))
            let restored = try await recorder.wait(after: bottom.sequence, description: "no-result editor returns unchanged") {
                !$0.helpIsPresented && $0.helpEditorFocused && $0.helpQuery("zzzzzz")
            }
            #expect(restored.focusedIdentity == empty.focusedIdentity)
            session.send(.key(.character("r"), modifiers: .ctrl))
            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(after: restored.sequence, description: "unavailable Run stays inert through a theme refresh") {
                !$0.helpIsPresented && $0.helpQuery("zzzzzz") && $0.raster.cells != restored.raster.cells
            }
            #expect(themed.helpContains("Runs: 0"))
        }
    }

    @Test("Theme and compact resize retain a native scrollable help cover and filtered results")
    func compactHelpScrolling() async throws {
        try await withHelpExample { session, surface, recorder in
            let before = try await filterHelpReview(session, recorder)
            session.send(.key(.character("?")))
            let opened = try await recorder.wait(after: before.sequence, description: "Browse help is visible") {
                $0.helpIsPresented && $0.helpContains("Browse")
            }
            let viewport = try await focusHelpControl(from: opened, session: session, recorder: recorder) {
                $0.helpViewportFocused
            }
            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(after: viewport.sequence, description: "help adopts the light theme with native viewport focus") {
                $0.helpIsPresented && $0.helpViewportFocused && $0.raster.cells != viewport.raster.cells
                    && $0.raster.cells.flatMap { $0 }.contains { $0.style?.foregroundColor == ChioTheme.light.colors.heading }
            }
            #expect(themed.focusedIdentity == viewport.focusedIdentity)
            surface.updateSurfaceSize(.init(width: 36, height: 18))
            session.requestSurfaceRefresh()
            let compact = try await recorder.wait(after: themed.sequence, description: "compact help retains its native viewport") {
                $0.helpIsPresented && $0.helpViewportFocused && $0.raster.size == CellSize(width: 36, height: 18)
            }
            #expect(compact.focusedIdentity == viewport.focusedIdentity)
            session.send(.key(.end))
            let bottom = try await recorder.wait(after: compact.sequence, description: "native End reveals the final help instructions") {
                $0.helpIsPresented && $0.helpContains("esc close") && $0.helpContains("Close help")
            }
            #expect(bottom.helpViewportFocused)
            #expect(bottom.focusedIdentity == viewport.focusedIdentity)
            session.send(.key(.home))
            let top = try await recorder.wait(after: bottom.sequence, description: "native Home returns to Browse shortcuts") {
                $0.helpIsPresented && $0.helpContains("Browse") && $0.helpContains("↑↓ move")
            }
            #expect(top.focusedIdentity == viewport.focusedIdentity)
            let close = try await focusHelpControl(from: top, session: session, recorder: recorder) {
                $0.helpButtonFocused("Close")
            }
            session.send(.key(.character("t"), modifiers: .ctrl))
            let closeThemed = try await recorder.wait(after: close.sequence, description: "Close advances to btop without losing native focus") {
                $0.helpIsPresented && $0.helpButtonFocused("Close") && $0.raster.cells != close.raster.cells
                    && $0.raster.cells.flatMap { $0 }.contains { $0.style?.foregroundColor == ChioTheme.btop.colors.heading }
            }
            #expect(closeThemed.focusedIdentity == close.focusedIdentity)
            session.send(.key(.escape))
            let restored = try await recorder.wait(after: closeThemed.sequence, description: "compact help restores the filtered Review results") {
                !$0.helpIsPresented && $0.helpResultsFocused && $0.helpQuery("Review")
                    && $0.helpSelectedRow("Review Agent") && $0.helpContains("Runs: 0")
            }
            #expect(restored.helpContains("Run") && restored.helpContains("Help"))
            #expect(restored.helpContains("? help") && restored.helpContains("^T theme") && restored.helpContains("^Q quit"))
        }
    }

    @Test("Ctrl-Q terminates the hosted example from the native viewport and Close button",
          arguments: [false, true])
    func quitFromHelp(closeFocused: Bool) async throws {
        let recorder = HostedFrameRecorder()
        let surface = HostedRasterSurface(surfaceSize: .init(width: 76, height: 30), appearance: .fallback,
                                          onFrame: { recorder.receive($0) })
        let session = try HostedSceneSession(for: HelpTestApp(), sceneID: "help-example-tests", surface: surface)
        let run = Task { try await session.start() }
        var deadline: Task<Void, Never>?
        defer { deadline?.cancel(); session.stop() }
        do {
            let ready = try await helpResultsReady(recorder)
            session.send(.key(.character("?")))
            let opened = try await recorder.wait(after: ready.sequence, description: "help is ready for termination shortcut") {
                $0.helpIsPresented && $0.helpContains("Browse")
            }
            _ = try await focusHelpControl(from: opened, session: session, recorder: recorder) {
                closeFocused ? $0.helpButtonFocused("Close") : $0.helpViewportFocused
            }
            deadline = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(5)) }
                catch { return }
                session.stop()
            }
            session.send(.key(.character("q"), modifiers: .ctrl))
            #expect(try await run.value == .programmatic)
        } catch {
            session.stop()
            _ = await run.result
            throw error
        }
    }

    @Test("The help example keeps content, status, actions and essential hints in both themes",
          arguments: [CellSize(width: 100, height: 30), CellSize(width: 50, height: 30),
                      CellSize(width: 36, height: 18)], ExampleTheme.allCases)
    func layout(size: CellSize, appearance: ExampleTheme) {
        let frame = DefaultRenderer().render(
            HelpExampleView(theme: appearance).environment(\.terminalSize, size),
            proposal: .init(width: size.width, height: size.height), frameInstant: .zero
        )
        let text = frame.rasterSurface.lines.joined(separator: "\n")
        #expect(frame.rasterSurface.size == size)
        #expect(text.contains("/ keyboard help"))
        #expect(text.contains("Build Agent"))
        #expect(text.contains("Runs: 0"))
        #expect(text.contains("Run") && text.contains("Help"))
        #expect(text.contains("↑↓ move") && text.contains("/ search") && text.contains("? help"))
        #expect(text.contains("^T theme") && text.contains("^Q quit"))
        #expect(frame.semanticSnapshot.accessibilityNodes.contains { $0.role == .button && $0.label == "Run" && $0.isEnabled })
        #expect(frame.semanticSnapshot.accessibilityNodes.contains { $0.role == .button && $0.label == "Help" && $0.isEnabled })
        let theme = appearance.theme
        #expect(frame.rasterSurface.cells.flatMap { $0 }.contains {
            $0.character == "?" && $0.style?.foregroundColor == theme.colors.accent
        })
    }
}

private struct HelpTestApp {
    nonisolated init() {}
}

extension HelpTestApp: App {
    var body: some Scene {
        WindowGroup(id: "help-example-tests") { HelpExampleView() }.exitOnKeys([])
    }
}

@MainActor
private func withHelpExample(
    perform: @MainActor (HostedSceneSession, HostedRasterSurface, HostedFrameRecorder) async throws -> Void
) async throws {
    let recorder = HostedFrameRecorder()
    let surface = HostedRasterSurface(surfaceSize: .init(width: 76, height: 30), appearance: .fallback,
                                      onFrame: { recorder.receive($0) })
    let session = try HostedSceneSession(for: HelpTestApp(), sceneID: "help-example-tests", surface: surface)
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
private func helpResultsReady(_ recorder: HostedFrameRecorder) async throws -> SemanticHostFrame {
    try await recorder.wait(description: "help example has initial Build selection and results focus") {
        !$0.helpIsPresented && $0.helpResultsFocused && $0.helpSelectedRow("Build Agent") && $0.helpContains("Runs: 0")
    }
}

@MainActor
private func filterHelpReview(_ session: HostedSceneSession, _ recorder: HostedFrameRecorder) async throws -> SemanticHostFrame {
    _ = try await helpResultsReady(recorder)
    session.sendInput(Array("/Review".utf8))
    _ = try await recorder.wait(description: "Review filter has reconciled the selected agent") {
        $0.helpEditorFocused && $0.helpQuery("Review") && $0.helpSelectedRow("Review Agent")
    }
    session.send(.key(.return))
    return try await recorder.wait(description: "Review results hold native keyboard focus") {
        $0.helpResultsFocused && $0.helpQuery("Review") && $0.helpSelectedRow("Review Agent")
            && $0.helpContains("1 of 4 items")
    }
}

@MainActor
private func focusHelpControl(
    from initial: SemanticHostFrame, session: HostedSceneSession, recorder: HostedFrameRecorder,
    matching predicate: @escaping @MainActor (SemanticHostFrame) -> Bool
) async throws -> SemanticHostFrame {
    var frame = initial
    for _ in 0..<10 {
        if predicate(frame) { return frame }
        let previous = frame
        session.send(.key(.tab))
        frame = try await recorder.wait(after: previous.sequence, description: "native Tab advances toward requested help control") {
            $0.focusedIdentity != previous.focusedIdentity
        }
    }
    try #require(predicate(frame), "Requested help control was not reachable through native Tab")
    return frame
}

private extension SemanticHostFrame {
    func helpContains(_ text: String) -> Bool { raster.lines.contains { $0.contains(text) } }
    var helpIsPresented: Bool { helpContains("Keyboard shortcuts") }
    func helpQuery(_ query: String) -> Bool {
        semantics.accessibilityNodes.contains { $0.role == .textField && $0.control?.value == .text(query) }
    }
    var helpEditorFocused: Bool {
        semantics.accessibilityNodes.contains { $0.identity == focusedIdentity && $0.role == .textField }
    }
    var helpResultsFocused: Bool {
        !helpIsPresented && !helpEditorFocused && !helpButtonFocused("Run") && !helpButtonFocused("Help")
            && semantics.focusRegions.contains { $0.identity == focusedIdentity }
    }
    func helpSelectedRow(_ name: String) -> Bool {
        raster.lines.contains { $0.contains(name) && $0.contains("›") }
    }
    func helpButtonFocused(_ label: String) -> Bool {
        semantics.accessibilityNodes.contains {
            $0.identity == focusedIdentity && $0.role == .button && $0.label == label
        }
    }
    var helpViewportFocused: Bool {
        semantics.accessibilityNodes.contains {
            $0.identity == focusedIdentity && ($0.role == .scrollView || $0.role == .scrollViewWithIndicators)
        }
    }
}
