@testable import ChioDashboard
import Chio
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct InboxExampleTests {
    @Test("Inbox retains native controls and hints at both preview thresholds and compact sizes",
          arguments: [CellSize(width: 100, height: 30), CellSize(width: 88, height: 26),
                      CellSize(width: 87, height: 26), CellSize(width: 88, height: 25),
                      CellSize(width: 60, height: 22), CellSize(width: 36, height: 18)], [false, true])
    func layout(size: CellSize, light: Bool) {
        let rendered = DefaultRenderer().render(
            InboxExampleView(light: light).environment(\.terminalSize, size),
            proposal: .init(width: size.width, height: size.height)
        )
        let text = rendered.rasterSurface.lines.joined(separator: "\n")
        #expect(rendered.rasterSurface.size == size)
        for value in ["review inbox", "Review (12)", "Recent", "#214", "^G queue", "^S sort", "^T theme", "^Q quit"] {
            #expect(text.contains(value))
        }
        let nodes = rendered.semanticSnapshot.accessibilityNodes
        for label in ["Queue", "Sort order"] {
            #expect(nodes.contains { $0.role == .picker && $0.label == label && $0.isEnabled })
        }
        #expect(nodes.contains { $0.role == .textField && $0.label == "Filter reviews…" })
        let hasPreview = size.width >= 88 && size.height >= 26
        #expect(text.contains("Preview") == hasPreview)
        #expect(text.contains("^P preview") == hasPreview)
        let theme: ChioTheme = light ? .light : .default
        #expect(rendered.rasterSurface.cells.flatMap { $0 }.contains {
            $0.style?.foregroundColor == theme.colors.accent
        })
    }

    @Test("Sorting, substring filtering, empty activation and queue changes reconcile stable selection")
    func filteringAndQueues() async throws {
        try await withInboxExample { session, _, recorder in
            let initial = try await inboxReady(recorder)
            session.send(.key(.arrowDown))
            let selected = try await recorder.wait(after: initial.sequence, description: "Down selects the next review") {
                $0.inboxSelected(215) && $0.inboxResultsFocused
            }
            session.send(.key(.character("s"), modifiers: .ctrl))
            let sorted = try await recorder.wait(after: selected.sequence, description: "repository sorting retains the selected identity") {
                $0.inboxContains("Repository") && $0.inboxSelected(215) && $0.inboxResultsFocused
            }
            session.sendInput(Array("/Chio".utf8))
            let filtered = try await recorder.wait(after: sorted.sequence, description: "substring query selects the first Chio review") {
                $0.inboxQuery("Chio") && $0.inboxEditorFocused && $0.inboxSelected(214)
                    && $0.inboxContains("5 of 12 items") && $0.inboxContains("Repository")
            }
            #expect(!filtered.semantics.accessibilityNodes.contains {
                $0.label?.hasPrefix("#215 ") == true
            })
            session.send([.key(.end)] + Array(repeating: .key(.backspace), count: 4))
            session.sendInput(Array("no-such-review".utf8))
            let empty = try await recorder.wait(after: filtered.sequence, description: "no substring matches clears selection and preview") {
                $0.inboxQuery("no-such-review") && $0.inboxContains("0 of 12 items")
                    && $0.inboxContains("No review selected.") && !$0.inboxSelected(214)
            }
            session.send([.key(.return), .key(.return)])
            session.requestSurfaceRefresh()
            let inert = try await recorder.wait(after: empty.sequence, description: "Return cannot activate an empty result set") {
                !$0.inboxReader && $0.inboxResultsFocused && $0.inboxQuery("no-such-review")
                    && $0.inboxContains("No review selected.")
            }
            session.send(.key(.escape))
            let recovered = try await recorder.wait(after: inert.sequence, description: "clearing query restores the first ordered review") {
                $0.inboxQuery("") && $0.inboxSelected(214) && $0.inboxContains("12 of 12 items")
            }
            session.sendInput(Array("/Chio\r".utf8))
            let chio = try await recorder.wait(after: recovered.sequence, description: "Chio query returns to native results") {
                $0.inboxQuery("Chio") && $0.inboxResultsFocused && $0.inboxSelected(214)
            }
            session.send(.key(.character("g"), modifiers: .ctrl))
            let drafts = try await recorder.wait(after: chio.sequence, description: "draft queue preserves query and selects its matching draft") {
                $0.inboxContains("Drafts (4)") && $0.inboxQuery("Chio")
                    && $0.inboxSelected(220) && $0.inboxContains("1 of 4 items")
            }
            session.send(.key(.character("g"), modifiers: .ctrl))
            let all = try await recorder.wait(after: drafts.sequence, description: "all queue retains the matching selected draft") {
                $0.inboxContains("All (16)") && $0.inboxQuery("Chio")
                    && $0.inboxSelected(220) && $0.inboxContains("6 of 16 items")
            }
            session.send(.key(.escape))
            _ = try await recorder.wait(after: all.sequence, description: "clearing the retained filter reveals all sixteen items") {
                $0.inboxContains("16 of 16 items") && $0.inboxSelected(220) && $0.inboxQuery("")
            }
        }
    }

    @Test("Search focus survives theme, preview and resize; native reader navigation restores list selection")
    func presentationAndReader() async throws {
        try await withInboxExample { session, surface, recorder in
            let ready = try await inboxReady(recorder)
            session.sendInput(Array("/214".utf8))
            let editing = try await recorder.wait(after: ready.sequence, description: "identity substring query has native editor focus") {
                $0.inboxQuery("214") && $0.inboxEditorFocused && $0.inboxSelected(214)
            }
            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(after: editing.sequence, description: "theme retains query, selection and native editor") {
                $0.inboxQuery("214") && $0.inboxSelected(214) && $0.inboxEditorFocused
                    && $0.focusedIdentity == editing.focusedIdentity && $0.raster.cells != editing.raster.cells
            }
            session.send(.key(.character("p"), modifiers: .ctrl))
            let hidden = try await recorder.wait(after: themed.sequence, description: "preview toggles without moving search focus") {
                !$0.inboxContains("Preview") && $0.inboxQuery("214") && $0.inboxSelected(214)
                    && $0.focusedIdentity == editing.focusedIdentity
            }
            surface.updateSurfaceSize(.init(width: 36, height: 18))
            session.requestSurfaceRefresh()
            let compact = try await recorder.wait(after: hidden.sequence, description: "compact resize retains native query editor") {
                $0.raster.size == CellSize(width: 36, height: 18) && $0.inboxQuery("214")
                    && $0.inboxSelected(214) && $0.focusedIdentity == editing.focusedIdentity
                    && $0.inboxContains("^Q quit")
            }
            surface.updateSurfaceSize(.init(width: 100, height: 30))
            session.requestSurfaceRefresh()
            let wide = try await recorder.wait(after: compact.sequence, description: "wide resize retains hidden preview and editor identity") {
                $0.raster.size == CellSize(width: 100, height: 30) && $0.inboxQuery("214")
                    && !$0.inboxContains("Preview") && $0.focusedIdentity == editing.focusedIdentity
            }
            session.send(.key(.escape))
            let list = try await recorder.wait(after: wide.sequence, description: "Escape clears the editor and returns to results") {
                $0.inboxResultsFocused && $0.inboxQuery("") && $0.inboxSelected(214)
            }
            session.sendInput(Array("/214\r\r".utf8))
            let opened = try await recorder.wait(after: list.sequence, description: "batched search and two Returns open the selected reader") {
                $0.inboxContains("chio / review #214") && $0.inboxViewportFocused
            }
            session.send(.key(.end))
            let end = try await recorder.wait(after: opened.sequence, description: "native End reveals the review footer") {
                $0.inboxContains("End of local review.") && $0.inboxViewportFocused
            }
            session.send(.key(.home))
            let home = try await recorder.wait(after: end.sequence, description: "native Home reveals the beginning of the review") {
                $0.inboxContains("Selection follows the visible results") && $0.inboxViewportFocused
            }
            session.send(.key(.tab))
            let tabbed = try await recorder.wait(after: home.sequence, description: "native Tab reaches a reader child without dismissing the cover") {
                $0.inboxReader && $0.focusedIdentity != nil && $0.focusedIdentity != home.focusedIdentity
            }
            session.send(.key(.character("t"), modifiers: .ctrl))
            let readerTheme = try await recorder.wait(after: tabbed.sequence, description: "reader theme changes preserve the focused child") {
                $0.inboxReader && $0.focusedIdentity == tabbed.focusedIdentity && $0.raster.cells != tabbed.raster.cells
            }
            session.send([.key(.character("g"), modifiers: .ctrl), .key(.character("s"), modifiers: .ctrl)])
            session.requestSurfaceRefresh()
            let isolated = try await recorder.wait(after: readerTheme.sequence, description: "background queue and sort shortcuts leave the reader snapshot intact") {
                $0.inboxContains("chio / review #214") && $0.focusedIdentity == tabbed.focusedIdentity
            }
            session.send(.key(.escape))
            _ = try await recorder.wait(after: isolated.sequence, description: "cover Escape restores native list focus and the filtered selected review") {
                !$0.inboxReader && $0.inboxResultsFocused && $0.inboxSelected(214) && $0.inboxQuery("214")
                    && $0.inboxContains("Review (12)") && $0.inboxContains("Recent")
                    && $0.focusedIdentity == list.focusedIdentity
            }
        }
    }

    @Test("Queue and sort shortcuts in the opening input batch cannot mutate the covered inbox")
    func pendingReaderIsolation() async throws {
        try await withInboxExample { session, _, recorder in
            let ready = try await inboxReady(recorder)
            session.sendInput(Array("/214\r\r\u{7}\u{19}".utf8))
            let opened = try await recorder.wait(after: ready.sequence, description: "pending cover consumes background shortcuts in the same read") {
                $0.inboxContains("chio / review #214") && $0.inboxViewportFocused
            }
            session.send(.key(.escape))
            _ = try await recorder.wait(after: opened.sequence, description: "dismissal proves the queue and sort stayed unchanged during the handoff") {
                !$0.inboxReader && $0.inboxResultsFocused && $0.inboxQuery("214") && $0.inboxSelected(214)
                    && $0.inboxContains("Review (12)") && $0.inboxContains("Recent")
            }
        }
    }

    @Test("Escape in the opening input batch cancels presentation without reopening the reader")
    func pendingReaderCancellation() async throws {
        try await withInboxExample { session, _, recorder in
            let ready = try await inboxReady(recorder)
            session.sendInput(Array("/214\r\r\u{1b}".utf8))
            let cancelled = try await recorder.wait(after: ready.sequence, description: "Escape cancels the pending reader and leaves results focused") {
                !$0.inboxReader && $0.inboxResultsFocused && $0.inboxQuery("214") && $0.inboxSelected(214)
            }
            session.send(.key(.character("g"), modifiers: .ctrl))
            _ = try await recorder.wait(after: cancelled.sequence, description: "a subsequent queue change proves cancellation remains committed") {
                !$0.inboxReader && $0.inboxContains("Drafts (4)") && $0.inboxQuery("214")
                    && $0.inboxContains("No review selected.")
            }
        }
    }
}

private struct InboxExampleTestApp {
    nonisolated init() {}
}

extension InboxExampleTestApp: App {
    var body: some Scene {
        WindowGroup(id: "inbox-example-tests") { InboxExampleView() }.exitOnKeys([])
    }
}

@MainActor
private func withInboxExample(
    perform: @MainActor (HostedSceneSession, HostedRasterSurface, HostedFrameRecorder) async throws -> Void
) async throws {
    let recorder = HostedFrameRecorder()
    let surface = HostedRasterSurface(surfaceSize: .init(width: 100, height: 30), appearance: .fallback,
                                      onFrame: { recorder.receive($0) })
    let session = try HostedSceneSession(for: InboxExampleTestApp(), sceneID: "inbox-example-tests", surface: surface)
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
private func inboxReady(_ recorder: HostedFrameRecorder) async throws -> SemanticHostFrame {
    try await recorder.wait(description: "inbox initially selects review 214 with native results focus") {
        $0.inboxSelected(214) && $0.inboxResultsFocused && $0.inboxContains("Review (12)")
    }
}

private extension SemanticHostFrame {
    func inboxContains(_ text: String) -> Bool { raster.lines.contains { $0.contains(text) } }
    var inboxReader: Bool { inboxContains("chio / review #") }
    func inboxQuery(_ value: String) -> Bool {
        semantics.accessibilityNodes.contains { $0.role == .textField && $0.control?.value == .text(value) }
    }
    func inboxSelected(_ id: Int) -> Bool {
        raster.lines.contains { $0.contains("#\(id) ") && $0.contains("›") }
    }
    var inboxEditorFocused: Bool {
        semantics.accessibilityNodes.contains { $0.identity == focusedIdentity && $0.role == .textField }
    }
    var inboxViewportFocused: Bool {
        semantics.accessibilityNodes.contains {
            $0.identity == focusedIdentity && ($0.role == .scrollView || $0.role == .scrollViewWithIndicators)
        }
    }
    var inboxResultsFocused: Bool {
        !inboxReader && !inboxEditorFocused && !semantics.accessibilityNodes.contains {
            $0.identity == focusedIdentity && $0.role == .picker
        } && semantics.focusRegions.contains { $0.identity == focusedIdentity }
    }
}
