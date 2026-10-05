@testable import ChioDashboard
import Chio
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct TreeExampleTests {
    @Test("The project tree keeps its hierarchy and actions across themes and sizes",
          arguments: [CellSize(width: 100, height: 30), CellSize(width: 50, height: 30),
                      CellSize(width: 36, height: 18)], [false, true])
    func layout(size: CellSize, light: Bool) {
        let rendered = DefaultRenderer().render(
            TreeExampleView(light: light).environment(\.terminalSize, size),
            proposal: .init(width: size.width, height: size.height), frameInstant: .zero
        )
        let text = rendered.rasterSurface.lines.joined(separator: "\n")
        #expect(rendered.rasterSurface.size == size)
        #expect(text.contains("/ project tree"))
        #expect(text.contains("SearchableList.swift"))
        #expect(text.contains("Expanded folders: 3 / 6"))
        #expect(text.contains("Expand all") && text.contains("Collapse all"))
        #expect(text.contains("^Q quit"))
        #expect(text.contains("▾ Sources") && text.contains("▸ Tests"))
        #expect(!text.contains("ThemeTests.swift"))
    }

    @Test("Parent collapse retains nested expansion choices through theme changes and resizing")
    func nestedExpansion() async throws {
        try await withTree { session, surface, recorder in
            let initial = try await recorder.wait(description: "Sources starts focused") { $0.treeFocused("Sources") }
            session.send(.key(.return))
            let closed = try await recorder.wait(after: initial.sequence, description: "Return closes the parent without pruning child choices") {
                $0.treeExpanded("Sources", false) && $0.treeContains("Expanded folders: 2 / 6")
                    && !$0.treeContains("SearchableList.swift")
            }
            #expect(closed.treeFocused("Sources"))
            session.send(.key(.space))
            _ = try await recorder.wait(after: closed.sequence, description: "Space restores the nested open branches") {
                $0.treeExpanded("Presentation", true) && $0.treeContains("SearchableList.swift")
            }
            try await focusTree("Presentation", session: session, recorder: recorder)
            session.send(.key(.space))
            _ = try await recorder.wait(description: "nested folder can close independently") {
                $0.treeExpanded("Presentation", false) && $0.treeContains("ChioTheme.swift")
                    && !$0.treeContains("SearchableList.swift")
            }
            try await focusTree("Sources", session: session, recorder: recorder)
            session.send(.key(.return))
            _ = try await recorder.wait(description: "parent closes with child decision retained") { $0.treeExpanded("Sources", false) }
            session.send(.key(.return))
            let reopened = try await recorder.wait(description: "parent reopens with Presentation still closed") {
                $0.treeExpanded("Sources", true) && $0.treeExpanded("Presentation", false)
                    && $0.treeContains("Expanded folders: 2 / 6")
            }
            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(after: reopened.sequence, description: "theme retains branch choices and focus") {
                $0.treeFocused("Sources") && $0.treeExpanded("Presentation", false)
                    && $0.raster.cells != reopened.raster.cells
            }
            surface.updateSurfaceSize(.init(width: 36, height: 18))
            session.requestSurfaceRefresh()
            _ = try await recorder.wait(after: themed.sequence, description: "compact tree retains hierarchy, choices and hints") {
                $0.raster.size == CellSize(width: 36, height: 18) && $0.treeFocused("Sources")
                    && $0.treeExpanded("Presentation", false) && $0.treeContains("^Q quit")
            }
        }
    }

    @Test("Native actions expand and collapse every folder, and an empty folder has a message")
    func bulkActionsAndEmptyBranch() async throws {
        try await withTree { session, _, recorder in
            _ = try await recorder.wait(description: "project tree ready") { $0.treeFocused("Sources") }
            try await focusTree("Expand all", session: session, recorder: recorder)
            session.send(.key(.return))
            _ = try await recorder.wait(description: "all six folder bindings are expanded") {
                $0.treeContains("Expanded folders: 6 / 6") && $0.treeExpanded("Notes", true)
            }
            try await focusTree("Collapse all", session: session, recorder: recorder)
            session.send(.key(.space))
            let collapsed = try await recorder.wait(description: "collapse resets all folder choices and preserves action focus") {
                $0.treeContains("Expanded folders: 0 / 6") && $0.treeFocused("Collapse all")
            }
            #expect(!collapsed.treeContains("ChioTheme.swift"))
            try await focusTree("Notes", session: session, recorder: recorder)
            session.send(.key(.return))
            _ = try await recorder.wait(description: "empty folder opens through native activation") {
                $0.treeExpanded("Notes", true) && $0.treeContains("No files yet.")
                    && $0.treeContains("Expanded folders: 1 / 6")
            }
        }
    }
}

private struct TreeTestApp {
    nonisolated init() {}
}

extension TreeTestApp: App {
    var body: some Scene {
        WindowGroup(id: "tree-tests") { TreeExampleView() }.exitOnKeys([])
    }
}

@MainActor
private func withTree(
    perform: @MainActor (HostedSceneSession, HostedRasterSurface, HostedFrameRecorder) async throws -> Void
) async throws {
    let recorder = HostedFrameRecorder()
    let surface = HostedRasterSurface(surfaceSize: .init(width: 100, height: 30), appearance: .fallback,
                                      onFrame: { recorder.receive($0) })
    let session = try HostedSceneSession(for: TreeTestApp(), sceneID: "tree-tests", surface: surface)
    let run = Task { try await session.start() }
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
private func focusTree(_ label: String, session: HostedSceneSession, recorder: HostedFrameRecorder) async throws {
    var frame = try await recorder.wait(description: "current tree focus") { $0.focusedIdentity != nil }
    for _ in 0..<12 {
        if frame.treeFocused(label) { return }
        let previous = frame.focusedIdentity
        session.send(.key(.tab))
        frame = try await recorder.wait(after: frame.sequence, description: "Tab advances native tree focus") {
            $0.focusedIdentity != nil && $0.focusedIdentity != previous
        }
    }
    Issue.record("Native focus did not reach \(label)")
}

private extension SemanticHostFrame {
    func treeContains(_ value: String) -> Bool { raster.lines.contains { $0.contains(value) } }
    func treeFocused(_ label: String) -> Bool {
        semantics.accessibilityNodes.contains { $0.identity == focusedIdentity && $0.label == label }
    }
    func treeExpanded(_ label: String, _ expanded: Bool) -> Bool {
        semantics.accessibilityNodes.contains {
            $0.role == .disclosureGroup && $0.label == label && $0.control?.value == .boolean(expanded)
        }
    }
}
