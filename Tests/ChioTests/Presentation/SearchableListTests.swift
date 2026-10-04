import Chio
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct SearchableListTests {
    @Test("A rejected query write preserves selection for the authoritative query")
    func rejectedQueryWrite() async throws {
        try await withSearchScene(rejectsQueryWrites: true) { session, _, recorder in
            let initial = try await recorder.wait(description: "constant empty query and Beta selection") {
                $0.hasResultsFocus && $0.contains("Q= S=b F=r A=0")
            }
            session.sendInput(Array("/al".utf8))
            session.send(.key(.character("b"), modifiers: .ctrl))
            let edited = try await recorder.wait(after: initial.sequence, description: "rejected query input processed") {
                $0.contains("Barrier=1")
            }
            #expect(edited.contains("Q= S=b"))
            #expect(edited.contains("4 of 4 items"))
        }
    }

    @Test("A slash and text arriving in one terminal read enters search without triggering shortcuts")
    func immediateSlashTyping() async throws {
        try await withSearchScene { session, _, recorder in
            _ = try await recorder.wait(description: "actual results focus before batched typing") {
                $0.hasResultsFocus && $0.contains("Q= S=b F=r A=0")
            }
            // A real terminal can deliver these bytes together before a focus
            // callback has rerendered the application. Do not wait between keys.
            session.sendInput(Array("/q".utf8))
            _ = try await recorder.wait(description: "batched slash-q edits the query and leaves quit untouched") {
                $0.hasQuery("q") && $0.contains("Q=q S=q F=s A=0")
                    && $0.contains("Quit=0") && $0.contains("1 of 4 items")
            }
        }
    }

    @Test("Batched search and two Enter keys activate the current filtered result once")
    func immediateSearchAndActivation() async throws {
        try await withSearchScene { session, _, recorder in
            let initial = try await recorder.wait(description: "results before batched search and activation") {
                $0.hasResultsFocus && $0.contains("Q= S=b F=r A=0")
            }
            session.sendInput(Array("/q\r\r".utf8))
            session.send(.key(.character("b"), modifiers: .ctrl))
            let completed = try await recorder.wait(after: initial.sequence, description: "all batched search and Enter input is processed") {
                $0.hasResultsFocus && $0.contains("Barrier=1")
            }
            let state = completed.raster.lines.first { $0.contains("Q=") }
            let activity = completed.raster.lines.first { $0.contains("Last=") }
            let queryIsCurrent = completed.hasQuery("q")
            let showsOneResult = completed.contains("1 of 4 items")
            #expect(state?.contains("Q=q S=q F=r A=1") == true)
            #expect(activity?.contains("Last=q Quit=0 Barrier=1") == true)
            #expect(queryIsCurrent)
            #expect(showsOneResult)
        }
    }

    @Test("Two Enter keys from the native search editor honor the pending results focus", arguments: ["q", "zzz"])
    func editorSearchAndActivation(query: String) async throws {
        try await withSearchScene { session, _, recorder in
            _ = try await recorder.wait(description: "results before entering the native editor") {
                $0.hasResultsFocus && $0.contains("Q= S=b F=r A=0")
            }
            session.send(.key(.character("/")))
            let editing = try await recorder.wait(description: "actual native editor owns focus") { frame in
                frame.semantics.accessibilityNodes.contains {
                    $0.identity == frame.focusedIdentity && $0.role == .textField
                }
            }
            session.sendInput(Array("\(query)\r\r".utf8))
            session.send(.key(.character("b"), modifiers: .ctrl))
            let completed = try await recorder.wait(after: editing.sequence, description: "editor batch and focus handoff complete") {
                $0.hasResultsFocus && $0.contains("Barrier=1") && $0.contains("F=r")
            }
            #expect(completed.hasQuery(query))
            #expect(completed.contains(query == "q" ? "Q=q S=q F=r A=1" : "Q=zzz S=- F=r A=0"))
            #expect(completed.contains(query == "q" ? "Last=q Quit=0 Barrier=1" : "Last=- Quit=0 Barrier=1"))
        }
    }

    @Test("Batched unmatched search and two Enter keys cannot activate a stale result")
    func immediateNoMatchActivation() async throws {
        try await withSearchScene { session, _, recorder in
            let initial = try await recorder.wait(description: "results before batched unmatched search") {
                $0.hasResultsFocus && $0.contains("Q= S=b F=r A=0")
            }
            session.sendInput(Array("/zzz\r\r".utf8))
            session.send(.key(.character("b"), modifiers: .ctrl))
            let completed = try await recorder.wait(after: initial.sequence, description: "all batched no-match and Enter input is processed") {
                $0.hasResultsFocus && $0.contains("Barrier=1")
            }
            let state = completed.raster.lines.first { $0.contains("Q=") }
            let activity = completed.raster.lines.first { $0.contains("Last=") }
            let queryIsCurrent = completed.hasQuery("zzz")
            let showsNoMatches = completed.contains("No matches.") && completed.contains("0 of 4 items")
            #expect(state?.contains("Q=zzz S=- F=r A=0") == true)
            #expect(activity?.contains("Last=- Quit=0 Barrier=1") == true)
            #expect(queryIsCurrent)
            #expect(showsNoMatches)
        }
    }

    @Test("Batched slash and Tab retain native results navigation without entering query text")
    func immediateSearchAndTab() async throws {
        try await withSearchScene { session, _, recorder in
            let initial = try await recorder.wait(description: "results before batched slash and Tab") {
                $0.hasResultsFocus && $0.contains("Q= S=b F=r A=0")
            }
            session.sendInput(Array("/\t".utf8))
            session.send(.key(.character("b"), modifiers: .ctrl))
            let tabbed = try await recorder.wait(after: initial.sequence, description: "batched Tab returns to native results focus") {
                $0.hasResultsFocus && $0.contains("Barrier=1") && $0.contains("F=r")
            }
            let tabState = tabbed.raster.lines.first { $0.contains("Q=") }
            let queryIsEmpty = tabbed.hasQuery("")
            #expect(tabState?.contains("Q= S=b F=r A=0") == true)
            #expect(queryIsEmpty)
            session.send(.key(.arrowUp))
            _ = try await recorder.wait(after: tabbed.sequence, description: "native arrows still select Alpha after batched Tab") {
                $0.hasResultsFocus && $0.contains("Q= S=a F=r A=0")
                    && $0.rowText("Alpha")?.contains("▌") == true
            }
            session.send(.key(.return))
            let activated = try await recorder.wait(description: "Enter activates Alpha after batched Tab and native navigation") {
                $0.contains("A=1")
            }
            let finalState = activated.raster.lines.first { $0.contains("Q=") }
            let finalActivity = activated.raster.lines.first { $0.contains("Last=") }
            #expect(finalState?.contains("Q= S=a F=r A=1") == true)
            #expect(finalActivity?.contains("Last=a Quit=0 Barrier=1") == true)
        }
    }

    @Test("Native Tab navigation reports search focus and preserves query without activating")
    func tabSearchFocus() async throws {
        try await withSearchScene { session, _, recorder in
            let initial = try await recorder.wait(description: "initial results before Shift-Tab") {
                $0.contains("Q= S=b F=r A=0") && $0.hasResultsFocus
            }
            session.send(.key(.tab, modifiers: .shift))
            let search = try await recorder.wait(description: "native Shift-Tab enters search") {
                $0.contains("Q= S=b F=s A=0")
            }
            #expect(search.focusedIdentity != initial.focusedIdentity)
            let searchHasEditingFocus = search.semantics.focusRegions.contains {
                $0.identity == search.focusedIdentity && $0.focusInteractions == .edit
            }
            #expect(searchHasEditingFocus)
            session.sendInput(Array("be".utf8))
            _ = try await recorder.wait(description: "search reached by Tab accepts text") {
                $0.contains("Q=be S=b F=s A=0") && $0.hasQuery("be")
            }
            session.send(.key(.tab))
            let results = try await recorder.wait(description: "native Tab leaves search and retains query") {
                $0.contains("Q=be S=b F=r A=0") && $0.hasQuery("be")
            }
            #expect(results.focusedIdentity != search.focusedIdentity)
            session.send(.key(.character("q")))
            _ = try await recorder.wait(description: "Tab updates the application's text-shortcut guard") {
                $0.contains("Q=be S=b F=r A=0") && $0.contains("Quit=1")
            }
        }
    }

    @Test("Enter after native Tab activates the visibly selected stable ID with one marker")
    func tabActivationMatchesVisibleSelection() async throws {
        try await withSearchScene { session, _, recorder in
            let initial = try await recorder.wait(description: "initial visibly selected beta") {
                $0.contains("Q= S=b F=r A=0") && $0.hasResultsFocus
            }
            let initiallyShowsBetaSelection = initial.contains("> Beta")
            let initialMarkerCount = initial.selectedMarkerCount
            let initialAlphaColumn = initial.rowColumn("Alpha")
            let initialBetaColumn = initial.rowColumn("Beta")
            #expect(initiallyShowsBetaSelection)
            #expect(initialMarkerCount == 1)
            #expect(initialAlphaColumn != nil)
            #expect(initialBetaColumn != nil)
            session.send(.key(.tab))
            session.send(.key(.character("b"), modifiers: .ctrl))
            let tabbed = try await recorder.wait(after: initial.sequence, description: "Tab has moved native focus") {
                $0.contains("Barrier=1")
            }
            #expect(tabbed.focusedIdentity != initial.focusedIdentity)
            let tabKeepsSelection = tabbed.contains("Q= S=b F=r A=0")
            let tabbedAlphaRow = tabbed.rowText("Alpha")
            let tabbedBetaRow = tabbed.rowText("Beta")
            let tabbedMarkerCount = tabbed.selectedMarkerCount
            let tabbedAlphaColumn = tabbed.rowColumn("Alpha")
            let tabbedBetaColumn = tabbed.rowColumn("Beta")
            #expect(tabKeepsSelection)
            #expect(tabbedAlphaRow?.contains("▌") == true)
            #expect(tabbedBetaRow?.contains("> Beta") == true)
            #expect(tabbedMarkerCount == 1)
            #expect(tabbedAlphaColumn == initialAlphaColumn)
            #expect(tabbedBetaColumn == initialBetaColumn)
            session.send(.key(.return))
            let activated = try await recorder.wait(description: "Enter after Tab activates once") {
                $0.contains("A=1")
            }
            let activatesSelectedBeta = activated.contains("Last=b")
            let retainsBetaSelection = activated.contains("S=b")
            #expect(activatesSelectedBeta)
            #expect(retainsBetaSelection)

            session.send(.key(.arrowDown))
            let focusedBeta = try await recorder.wait(after: activated.sequence, description: "native arrow moves Alpha focus to Beta") {
                $0.contains("Q= S=b F=r A=1") && $0.rowText("Beta")?.contains("▌") == true
            }
            let betaHasSelectionMarker = focusedBeta.rowText("Beta")?.contains("> Beta") == true
            #expect(betaHasSelectionMarker)
            session.send(.key(.arrowDown))
            let focusedQuill = try await recorder.wait(after: focusedBeta.sequence, description: "native arrow moves Beta focus and selection to Quill") {
                $0.contains("Q= S=q F=r A=1") && $0.rowText("Quill")?.contains("▌") == true
            }
            let quillHasSelectionMarker = focusedQuill.rowText("Quill")?.contains("> Quill") == true
            let finalMarkerCount = focusedQuill.selectedMarkerCount
            #expect(quillHasSelectionMarker)
            #expect(finalMarkerCount == 1)
        }
    }

    @Test("Omitting query binding retains internal search through theme and resize")
    func internalQueryLifecycle() async throws {
        try await withSearchScene(usesInternalQuery: true) { session, surface, recorder in
            _ = try await recorder.wait(description: "internal query starts empty") {
                $0.contains("Q= S=b F=r A=0") && $0.hasResultsFocus && $0.hasQuery("")
            }
            session.send(.key(.character("/")))
            _ = try await recorder.wait(description: "internal query search focus") { $0.contains("F=s") }
            session.sendInput(Array("q".utf8))
            _ = try await recorder.wait(description: "internal query filters without an external binding") {
                $0.hasQuery("q") && $0.contains("1 of 4 items") && $0.contains("Q= S=q F=s A=0")
            }
            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(description: "theme retains internally owned query") {
                $0.hasQuery("q") && $0.contains("Theme=light") && $0.contains("S=q F=s A=0")
            }
            surface.updateSurfaceSize(.init(width: 32, height: 14))
            session.requestSurfaceRefresh()
            _ = try await recorder.wait(after: themed.sequence, description: "resize retains internally owned query") {
                $0.raster.size.width == 32 && $0.hasQuery("q") && $0.contains("S=q F=s A=0")
            }
            session.send(.key(.return))
            _ = try await recorder.wait(description: "internal query Enter retains filter in results") {
                $0.hasQuery("q") && $0.contains("S=q F=r A=0")
            }
            session.send(.key(.return))
            _ = try await recorder.wait(description: "internal query result activates") {
                $0.contains("A=1") && $0.contains("Last=q")
            }
            session.send(.key(.character("/")))
            _ = try await recorder.wait(description: "internal query refocuses search") { $0.contains("F=s") }
            session.send(.key(.escape))
            _ = try await recorder.wait(description: "Escape clears the internal query") {
                $0.hasQuery("") && $0.contains("4 of 4 items") && $0.contains("S=q F=r A=1")
            }
        }
    }

    @Test("Search editing protects text shortcuts and Enter separates focus from activation")
    func searchFocusAndActivation() async throws {
        try await withSearchScene { session, _, recorder in
            _ = try await recorder.wait(description: "initial result focus") {
                $0.contains("Q= S=b F=r A=0") && $0.hasResultsFocus
            }

            session.send(.key(.character("/")))
            let search = try await recorder.wait(description: "slash focuses search") {
                $0.contains("Q= S=b F=s A=0")
            }
            let searchHasEditingFocus = search.semantics.focusRegions.contains {
                $0.identity == search.focusedIdentity && $0.focusInteractions == .edit
            }
            #expect(searchHasEditingFocus)

            // Exercise the public terminal-byte input path as well as normalized keys.
            session.sendInput(Array("q".utf8))
            let filtered = try await recorder.wait(description: "q is entered and filters immediately") {
                $0.contains("Q=q S=q F=s A=0") && $0.contains("1 of 4 items")
            }
            let showsQuill = filtered.contains("Quill")
            let showsAlpha = filtered.contains("Alpha")
            let hasNotQuit = filtered.contains("Quit=0")
            #expect(showsQuill)
            #expect(!showsAlpha)
            #expect(hasNotQuit)

            session.send(.key(.return))
            let results = try await recorder.wait(description: "first Enter returns to results") {
                $0.contains("Q=q S=q F=r A=0")
            }
            #expect(results.focusedIdentity != search.focusedIdentity)
            let hasNotActivated = results.contains("Last=-")
            #expect(hasNotActivated)

            session.send(.key(.return))
            _ = try await recorder.wait(description: "second Enter activates the selected result") {
                $0.contains("Q=q S=q F=r A=1") && $0.contains("Last=q")
            }

            session.send(.key(.character("/")))
            _ = try await recorder.wait(description: "search can be focused again") {
                $0.contains("Q=q S=q F=s A=1")
            }
            session.send(.key(.escape))
            _ = try await recorder.wait(description: "search Escape clears and returns to results") {
                $0.contains("Q= S=q F=r A=1") && $0.contains("4 of 4 items")
            }

            session.send(.key(.character("q")))
            _ = try await recorder.wait(description: "application shortcut works in results") {
                $0.contains("Quit=1") && $0.contains("Q= S=q F=r A=1")
            }
        }
    }

    @Test("Filtering preserves stable selection, reconciles missing IDs, and never activates")
    func stableSelectionThroughFilteringAndNoMatches() async throws {
        try await withSearchScene { session, _, recorder in
            _ = try await recorder.wait(description: "initial selection") {
                $0.contains("Q= S=b F=r A=0") && $0.hasResultsFocus
            }
            session.send(.key(.arrowDown))
            _ = try await recorder.wait(description: "native down arrow selects next stable ID") {
                $0.contains("Q= S=q F=r A=0")
            }
            session.send(.key(.arrowUp))
            _ = try await recorder.wait(description: "native up arrow returns to beta") {
                $0.contains("Q= S=b F=r A=0")
            }

            session.send(.key(.character("/")))
            _ = try await recorder.wait(description: "search focus") { $0.contains("F=s") }
            session.send(.key(.character("a")))
            _ = try await recorder.wait(description: "visible beta selection is preserved") {
                $0.contains("Q=a S=b F=s A=0") && $0.contains("3 of 4 items")
            }
            session.send(.key(.character("l")))
            _ = try await recorder.wait(description: "hidden beta is replaced by first match") {
                $0.contains("Q=al S=a F=s A=0") && $0.contains("1 of 4 items")
            }
            session.sendInput(Array("zz".utf8))
            let empty = try await recorder.wait(description: "no matches clears selection") {
                $0.contains("Q=alzz S=- F=s A=0") && $0.contains("0 of 4 items")
            }
            let showsNoMatches = empty.contains("No matches.")
            let showsNoItems = empty.contains("No items yet.")
            #expect(showsNoMatches)
            #expect(!showsNoItems)

            session.send(.key(.return))
            _ = try await recorder.wait(description: "empty results can receive focus") {
                $0.contains("Q=alzz S=- F=r A=0")
            }
            session.send(.key(.return))
            // This observed application event is a queue barrier: the preceding
            // activation key has been processed, even when it changes no state.
            session.send(.key(.character("b"), modifiers: .ctrl))
            _ = try await recorder.wait(description: "no selection cannot activate") {
                $0.contains("Barrier=1") && $0.contains("A=0") && $0.contains("Last=-")
            }
            session.send(.key(.escape))
            _ = try await recorder.wait(description: "results Escape clears filter and chooses first ID") {
                $0.contains("Q= S=a F=r A=0") && $0.contains("4 of 4 items")
            }
        }
    }

    @Test("Theme switching and narrow resize preserve query, selection, and editing focus")
    func themeAndResizePreserveInteractionState() async throws {
        try await withSearchScene { session, surface, recorder in
            _ = try await recorder.wait(description: "initial result focus") {
                $0.contains("Q= S=b F=r A=0") && $0.hasResultsFocus
            }
            session.send(.key(.character("/")))
            _ = try await recorder.wait(description: "search focus") { $0.contains("F=s") }
            session.sendInput(Array("be".utf8))
            let before = try await recorder.wait(description: "beta search") {
                $0.contains("Q=be S=b F=s A=0") && $0.contains("Theme=dark")
            }
            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(description: "light theme keeps search state") {
                $0.contains("Q=be S=b F=s A=0") && $0.contains("Theme=light")
            }
            #expect(themed.focusedIdentity == before.focusedIdentity)
            let appearanceChanged = themed.raster.cells != before.raster.cells
            let markerUsesLightAccent = themed.raster.cells.flatMap { $0 }.contains {
                $0.character == ">" && $0.style?.foregroundColor == ChioTheme.light.colors.accent
            }
            #expect(appearanceChanged)
            #expect(markerUsesLightAccent)

            surface.updateSurfaceSize(.init(width: 32, height: 14))
            session.requestSurfaceRefresh()
            let resized = try await recorder.wait(after: themed.sequence, description: "narrow resized frame") {
                $0.raster.size.width == 32 && $0.contains("Q=be S=b F=s A=0")
            }
            #expect(resized.focusedIdentity == themed.focusedIdentity)
            session.send(.key(.character("t")))
            _ = try await recorder.wait(description: "typing continues after theme and resize") {
                $0.contains("Q=bet S=b F=s A=0") && $0.contains("Quit=0")
            }
        }
    }
}

private struct SearchItem {
    let id: String
    let name: String

    static let fixtures = [
        SearchItem(id: "a", name: "Alpha"),
        SearchItem(id: "b", name: "Beta"),
        SearchItem(id: "q", name: "Quill"),
        SearchItem(id: "g", name: "Gamma"),
    ]
}

extension SearchItem: Identifiable {}
extension SearchItem: Sendable {}

private struct SearchTestApp {
    let usesInternalQuery: Bool
    let rejectsQueryWrites: Bool

    nonisolated init() { usesInternalQuery = false; rejectsQueryWrites = false }

    nonisolated init(usesInternalQuery: Bool, rejectsQueryWrites: Bool = false) {
        self.usesInternalQuery = usesInternalQuery
        self.rejectsQueryWrites = rejectsQueryWrites
    }
}

extension SearchTestApp: App {
    var body: some Scene {
        WindowGroup(id: "search-tests") {
            SearchTestView(usesInternalQuery: usesInternalQuery, rejectsQueryWrites: rejectsQueryWrites)
        }
            .exitOnKeys([])
    }
}

@MainActor
private struct SearchTestView {
    let usesInternalQuery: Bool
    let rejectsQueryWrites: Bool
    @State private var query = ""
    @State private var selection: String? = "b"
    @State private var searchFocused = false
    @State private var activationCount = 0
    @State private var lastActivation: String?
    @State private var quitCount = 0
    @State private var barrier = 0
    @State private var lightTheme = false

    private var theme: ChioTheme {
        var theme = lightTheme ? ChioTheme.light : .default
        theme = theme.replacing(treatments: theme.treatments.replacing(selectionMarker: ">"))
        return theme
    }
}

extension SearchTestView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SearchableList(SearchItem.fixtures, selection: $selection,
                           query: usesInternalQuery ? nil : (rejectsQueryWrites ? .constant("") : $query),
                           searchText: \.name) {
                Text($0.name)
            }
            .filtering(.fuzzy)
            .onActivate { item in
                activationCount += 1
                lastActivation = item.id
            }
            .onSearchFocusChange { searchFocused = $0 }
            .onResultKeyPress { press in
                guard press == KeyPress(.character("q")) else { return .ignored }
                quitCount += 1
                return .handled
            }
            Text("Q=\(query) S=\(selection ?? "-") F=\(searchFocused ? "s" : "r") A=\(activationCount)")
            Text("Last=\(lastActivation ?? "-") Quit=\(quitCount) Barrier=\(barrier)")
            Text("Theme=\(lightTheme ? "light" : "dark")")
        }
        .chioTheme(theme)
        .onKeyPress { press in
            if press == KeyPress(.character("t"), modifiers: .ctrl) {
                lightTheme.toggle()
                return .handled
            }
            if press == KeyPress(.character("b"), modifiers: .ctrl) {
                barrier += 1
                return .handled
            }
            return .ignored
        }
    }
}

@MainActor
private func withSearchScene(
    usesInternalQuery: Bool = false,
    rejectsQueryWrites: Bool = false,
    perform: @MainActor (HostedSceneSession, HostedRasterSurface, HostedFrameRecorder) async throws -> Void
) async throws {
    let recorder = HostedFrameRecorder()
    let surface = HostedRasterSurface(
        surfaceSize: .init(width: 60, height: 18),
        appearance: .fallback,
        onFrame: { recorder.receive($0) }
    )
    let session = try HostedSceneSession(
        for: SearchTestApp(usesInternalQuery: usesInternalQuery, rejectsQueryWrites: rejectsQueryWrites),
        sceneID: "search-tests", surface: surface
    )
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
    var hasResultsFocus: Bool {
        guard let focusedIdentity,
              semantics.focusRegions.contains(where: { $0.identity == focusedIdentity }) else {
            return false
        }
        return !semantics.accessibilityNodes.contains {
            $0.identity == focusedIdentity && $0.role == .textField
        }
    }

    var selectedMarkerCount: Int {
        raster.cells.flatMap { $0 }.filter { $0.character == ">" }.count
    }

    func hasQuery(_ value: String) -> Bool {
        semantics.accessibilityNodes.contains { $0.role == .textField && $0.control?.value == .text(value) }
    }

    func contains(_ text: String) -> Bool {
        raster.lines.contains { $0.contains(text) }
    }

    func rowText(_ name: String) -> String? {
        raster.lines.first { $0.contains(name) }
    }

    func rowColumn(_ name: String) -> Int? {
        guard let firstCharacter = name.first,
              let row = raster.lines.firstIndex(where: { $0.contains(name) }) else { return nil }
        return raster.cells[row].firstIndex { $0.character == firstCharacter }
    }
}
