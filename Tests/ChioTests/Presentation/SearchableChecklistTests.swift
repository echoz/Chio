import Chio
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct SearchableChecklistTests {
    @Test("Search Return enters the first native row; arrows move focus and Space/Return toggle once")
    func nativeRowMembership() async throws {
        try await withChecklistScene { session, _, recorder in
            let search = try await recorder.wait(description: "initial native search focus") {
                $0.checklistSearchFocused && $0.checklistContains("S=-")
            }
            session.send(.key(.return))
            let first = try await recorder.wait(after: search.sequence, description: "first native Alpha row") {
                $0.checklistRowFocused("Alpha")
            }
            #expect(first.checklistContains("S=-"))
            #expect(first.focusedIdentity != search.focusedIdentity)
            session.send(.key(.arrowDown))
            let second = try await recorder.wait(after: first.sequence, description: "native Beta focus without checking") {
                $0.checklistRowFocused("Beta")
            }
            #expect(second.checklistContains("S=-"))
            session.send(.key(.space))
            let checked = try await recorder.wait(after: second.sequence, description: "Space checks Beta once") {
                $0.checklistContains("S=b") && $0.checklistRow("Beta")?.contains("[x]") == true
            }
            session.send(.key(.return))
            let unchecked = try await recorder.wait(after: checked.sequence, description: "Return unchecks Beta once") {
                $0.checklistContains("S=-") && $0.checklistRow("Beta")?.contains("[ ]") == true
            }
            #expect(unchecked.checklistRowFocused("Beta"))
        }
    }

    @Test("Filtering preserves hidden checked IDs while another matching row is toggled")
    func hiddenMembership() async throws {
        try await withChecklistScene(selection: ["a", "b"]) { session, _, recorder in
            _ = try await recorder.wait(description: "initial checked Alpha and Beta") { $0.checklistSearchFocused }
            session.sendInput(Array("qu".utf8))
            let filtered = try await recorder.wait(description: "Quill filter preserves two hidden checks") {
                $0.checklistQuery("qu") && $0.checklistContains("1 of 4 items · 2 selected")
                    && $0.checklistContains("2 hidden · 0 unavailable")
            }
            #expect(filtered.checklistContains("S=a,b"))
            session.send(.key(.return))
            _ = try await recorder.wait(description: "filtered native Quill focus") { $0.checklistRowFocused("Quill") }
            session.send(.key(.space))
            _ = try await recorder.wait(description: "Quill joins hidden checks") { $0.checklistContains("S=a,b,q") }
            session.send(.key(.escape))
            let cleared = try await recorder.wait(description: "cleared query restores all three checkmarks") {
                $0.checklistQuery("") && $0.checklistContains("4 of 4 items · 3 selected")
            }
            for label in ["Alpha", "Beta", "Quill"] {
                #expect(cleared.checklistRow(label)?.contains("[x]") == true)
            }
        }
    }

    @Test("Disabled rows cannot change membership and external selection remains authoritative")
    func disabledMembership() async throws {
        try await withChecklistScene(selection: ["b"], disabledIDs: ["a", "b"]) { session, _, recorder in
            _ = try await recorder.wait(description: "disabled initial choices") { $0.checklistSearchFocused }
            session.send(.key(.return))
            _ = try await recorder.wait(description: "native disabled row focus") { !$0.checklistSearchFocused }
            session.send(.key(.character("/")))
            _ = try await recorder.wait(description: "search disabled unchecked Alpha") { $0.checklistSearchFocused }
            session.sendInput(Array("al".utf8))
            _ = try await recorder.wait(description: "only disabled Alpha visible") { $0.checklistQuery("al") }
            session.send(.key(.return))
            let alpha = try await recorder.wait(description: "disabled Alpha native focus") { $0.checklistRowFocused("Alpha") }
            session.send(.key(.space))
            session.send(.key(.character("b"), modifiers: .ctrl))
            let rejectedAdd = try await recorder.wait(after: alpha.sequence, description: "disabled unchecked row processed") {
                $0.checklistContains("Barrier=1")
            }
            #expect(rejectedAdd.checklistContains("S=b"))
            #expect(rejectedAdd.checklistRow("Alpha")?.contains("[ ]") == true)
            session.send(.key(.character("/")))
            _ = try await recorder.wait(description: "search before disabled Beta") { $0.checklistSearchFocused }
            session.send(.key(.escape))
            _ = try await recorder.wait(description: "Escape restores native results") { !$0.checklistSearchFocused && $0.checklistQuery("") }
            session.send(.key(.character("/")))
            _ = try await recorder.wait(description: "editing Beta query") { $0.checklistSearchFocused }
            session.sendInput(Array("be".utf8))
            _ = try await recorder.wait(description: "disabled checked Beta match") { $0.checklistQuery("be") }
            session.send(.key(.return))
            let beta = try await recorder.wait(description: "disabled checked Beta focus") { $0.checklistRowFocused("Beta") }
            session.send(.key(.return))
            session.send(.key(.character("b"), modifiers: .ctrl))
            let rejectedRemove = try await recorder.wait(after: beta.sequence, description: "disabled checked Return processed") {
                $0.checklistContains("Barrier=2")
            }
            #expect(rejectedRemove.checklistContains("S=b"))
            #expect(rejectedRemove.checklistRow("Beta")?.contains("[x]") == true)
            session.send(.key(.character("x"), modifiers: .ctrl))
            let external = try await recorder.wait(description: "external checked-set replacement") {
                $0.checklistContains("S=a,q")
            }
            #expect(external.checklistContains("2 selected"))
            #expect(external.checklistRow("Beta")?.contains("[ ]") == true)
        }
    }

    @Test("Removed, reordered, empty, restored and newly disabled options never prune checked IDs")
    func dynamicOptions() async throws {
        try await withChecklistScene(selection: ["a", "b"]) { session, _, recorder in
            _ = try await recorder.wait(description: "initial dynamic choices") { $0.checklistSearchFocused }
            session.send(.key(.return))
            _ = try await recorder.wait(description: "native row focus before source changes") { $0.checklistRowFocused("Alpha") }
            session.send(.key(.character("d"), modifiers: .ctrl))
            let removed = try await recorder.wait(description: "Alpha removed and remaining rows reordered") {
                $0.checklistContains("Revision=1") && $0.checklistContains("3 of 3 items · 2 selected")
            }
            #expect(removed.checklistContains("S=a,b"))
            #expect(removed.checklistContains("0 hidden · 1 unavailable"))
            session.send(.key(.character("e"), modifiers: .ctrl))
            let disabled = try await recorder.wait(after: removed.sequence, description: "Beta becomes unavailable") {
                $0.checklistContains("0 hidden · 2 unavailable")
            }
            #expect(disabled.checklistRow("Beta")?.contains("[x]") == true)
            session.send(.key(.character("d"), modifiers: .ctrl))
            let empty = try await recorder.wait(after: disabled.sequence, description: "all options removed") {
                $0.checklistContains("Revision=2") && $0.checklistContains("No items yet.")
            }
            #expect(empty.checklistContains("S=a,b"))
            #expect(empty.checklistContains("0 of 0 items · 2 selected"))
            #expect(empty.checklistContains("0 hidden · 2 unavailable"))
            session.send(.key(.return))
            session.send(.key(.character("b"), modifiers: .ctrl))
            let stillSearch = try await recorder.wait(after: empty.sequence, description: "empty Return retains editor") {
                $0.checklistContains("Barrier=1") && $0.checklistSearchFocused
            }
            #expect(stillSearch.checklistContains("S=a,b"))
            session.send(.key(.character("d"), modifiers: .ctrl))
            let restored = try await recorder.wait(description: "restored reordered choices") {
                $0.checklistContains("Revision=3") && $0.checklistContains("4 of 4 items · 2 selected")
            }
            #expect(restored.checklistRow("Alpha")?.contains("[x]") == true)
            #expect(restored.checklistRow("Beta")?.contains("[x]") == true)
            session.send(.key(.character("e"), modifiers: .ctrl))
            let enabled = try await recorder.wait(after: restored.sequence, description: "all checked choices available again") {
                !$0.checklistContains("unavailable")
            }
            #expect(enabled.checklistContains("S=a,b"))
        }
    }

    @Test("Rejected and transformed query and membership writes display retained binding values",
          arguments: [false, true])
    func authoritativeBindings(transformed: Bool) async throws {
        let policy: ChecklistWritePolicy = transformed ? .transformed : .constant
        try await withChecklistScene(selection: ["a"], writePolicy: policy) { session, _, recorder in
            let initial = try await recorder.wait(description: "authoritative bindings editor") { $0.checklistSearchFocused }
            session.sendInput(Array((policy == .constant ? "zzz" : "QU").utf8))
            session.send(.key(.character("b"), modifiers: .ctrl))
            let edited = try await recorder.wait(after: initial.sequence, description: "query binding retained qu") {
                $0.checklistContains("Barrier=1") && $0.checklistQuery("qu")
            }
            #expect(edited.checklistContains("1 of 4 items · 1 selected"))
            session.send(.key(.return))
            let row = try await recorder.wait(description: "native authoritative Quill focus") { $0.checklistRowFocused("Quill") }
            session.send(.key(.space))
            session.send(.key(.character("b"), modifiers: .ctrl))
            let retained = try await recorder.wait(after: row.sequence, description: "membership binding retained Alpha only") {
                $0.checklistContains("Barrier=2")
            }
            #expect(retained.checklistContains("S=a"))
            #expect(retained.checklistRow("Quill")?.contains("[ ]") == true)
            #expect(retained.checklistContains("1 selected"))
        }
    }

    @Test("Internal query, checked membership and native row focus survive theme and narrow resize")
    func internalQueryThemeAndResize() async throws {
        try await withChecklistScene(selection: ["a"], internalQuery: true) { session, surface, recorder in
            _ = try await recorder.wait(description: "internal query editor") { $0.checklistSearchFocused }
            session.sendInput(Array("qu".utf8))
            _ = try await recorder.wait(description: "internal filtered Quill") { $0.checklistQuery("qu") }
            session.send(.key(.return))
            let row = try await recorder.wait(description: "internal query native row") { $0.checklistRowFocused("Quill") }
            session.send(.key(.space))
            _ = try await recorder.wait(description: "Quill checked alongside hidden Alpha") { $0.checklistContains("S=a,q") }
            session.send(.key(.character("t"), modifiers: .ctrl))
            var previous = try await recorder.wait(description: "light theme retains query and row") {
                $0.checklistContains("Theme=light") && $0.checklistRowFocused("Quill") && $0.checklistQuery("qu")
            }
            #expect(previous.focusedIdentity == row.focusedIdentity)
            for width in [32, 36] {
                surface.updateSurfaceSize(.init(width: width, height: 18))
                session.requestSurfaceRefresh()
                let resized = try await recorder.wait(after: previous.sequence, description: "checklist at width \(width)") {
                    $0.raster.size.width == width && $0.checklistQuery("qu") && $0.checklistRowFocused("Quill")
                }
                #expect(resized.focusedIdentity == row.focusedIdentity)
                #expect(resized.checklistContains("S=a,q"))
                previous = resized
            }
            session.send(.key(.character("/")))
            _ = try await recorder.wait(description: "internal editor refocused") { $0.checklistSearchFocused }
            session.send(.key(.backspace))
            _ = try await recorder.wait(description: "editing continues after resize") { $0.checklistQuery("q") }
        }
    }

    @Test("Batched slash, filter, Return and Space consume handoff keys without stale toggles")
    func batchedSearchHandoff() async throws {
        try await withChecklistScene { session, _, recorder in
            _ = try await recorder.wait(description: "batch fixture search focus") { $0.checklistSearchFocused }
            session.send(.key(.return))
            let alpha = try await recorder.wait(description: "batch fixture Alpha focus") { $0.checklistRowFocused("Alpha") }
            session.sendInput(Array("/q\r \r".utf8))
            session.send(.key(.character("b"), modifiers: .ctrl))
            let handedOff = try await recorder.wait(after: alpha.sequence, description: "batch completes on filtered Quill") {
                $0.checklistContains("Barrier=1") && $0.checklistRowFocused("Quill")
            }
            #expect(handedOff.checklistQuery("q"))
            #expect(handedOff.checklistContains("S=-"))
            #expect(handedOff.checklistContains("1 of 4 items · 0 selected"))
            #expect(handedOff.checklistContains("Quit=0"))
            session.send(.key(.space))
            let checked = try await recorder.wait(description: "fresh Space toggles current row") { $0.checklistContains("S=q") }
            session.send(.key(.character("q")))
            _ = try await recorder.wait(after: checked.sequence, description: "results-only application shortcut works after handoff") {
                $0.checklistContains("Quit=1") && $0.checklistQuery("q")
            }
        }
    }

    @Test("No-match Return retains search editing and cannot toggle a stale choice")
    func noMatchEditing() async throws {
        try await withChecklistScene(selection: ["a"]) { session, _, recorder in
            _ = try await recorder.wait(description: "no-match initial editor") { $0.checklistSearchFocused }
            session.sendInput(Array("zzz\r".utf8))
            session.send(.key(.character("b"), modifiers: .ctrl))
            let unmatched = try await recorder.wait(description: "unmatched Return keeps editor") {
                $0.checklistContains("Barrier=1") && $0.checklistSearchFocused
                    && $0.checklistContains("No matches.")
            }
            #expect(unmatched.checklistQuery("zzz"))
            #expect(unmatched.checklistContains("S=a"))
            session.sendInput(Array("x".utf8))
            _ = try await recorder.wait(after: unmatched.sequence, description: "no-match text still edits natively") {
                $0.checklistQuery("zzzx") && $0.checklistSearchFocused
            }
        }
    }

    @Test("Native arrows reveal offscreen rows while checked membership stays independent")
    func nativeScrolling() async throws {
        try await withChecklistScene(longList: true, height: 14) { session, _, recorder in
            _ = try await recorder.wait(description: "long-list initial editor") { $0.checklistSearchFocused }
            session.send(.key(.return))
            var previous = try await recorder.wait(description: "first long-list native row") { $0.checklistRowFocused("Option 00") }
            for index in 1...14 {
                session.send(.key(.arrowDown))
                let label = "Option \(index < 10 ? "0" : "")\(index)"
                previous = try await recorder.wait(after: previous.sequence, description: "native reveal \(label)") {
                    $0.checklistRowFocused(label)
                }
                #expect(previous.checklistContains("S=-"))
            }
            #expect(previous.checklistRow("Option 00") == nil)
            session.send(.key(.space))
            let checked = try await recorder.wait(after: previous.sequence, description: "offscreen-navigation target checked") {
                $0.checklistContains("S=14")
            }
            #expect(checked.checklistRow("Option 14")?.contains("[x]") == true)
        }
    }
}

private enum ChecklistWritePolicy {
    case ordinary
    case constant
    case transformed
}

extension ChecklistWritePolicy: Equatable {}
extension ChecklistWritePolicy: Sendable {}

private struct ChecklistItem {
    let id: String
    let name: String

    static let fixtures = [
        Self(id: "a", name: "Alpha"), Self(id: "b", name: "Beta"),
        Self(id: "q", name: "Quill"), Self(id: "g", name: "Gamma"),
    ]
}

extension ChecklistItem: Identifiable {}
extension ChecklistItem: Sendable {}

private struct ChecklistTestApp {
    let selection: Set<String>
    let disabledIDs: Set<String>
    let internalQuery: Bool
    let writePolicy: ChecklistWritePolicy
    let longList: Bool

    nonisolated init() {
        selection = []; disabledIDs = []; internalQuery = false
        writePolicy = .ordinary; longList = false
    }

    nonisolated init(selection: Set<String>, disabledIDs: Set<String>, internalQuery: Bool,
                     writePolicy: ChecklistWritePolicy, longList: Bool) {
        self.selection = selection
        self.disabledIDs = disabledIDs
        self.internalQuery = internalQuery
        self.writePolicy = writePolicy
        self.longList = longList
    }
}

extension ChecklistTestApp: App {
    var body: some Scene {
        WindowGroup(id: "checklist-tests") {
            ChecklistTestView(initialSelection: selection, disabledIDs: disabledIDs,
                              internalQuery: internalQuery, writePolicy: writePolicy, longList: longList)
        }.exitOnKeys([])
    }
}

@MainActor
private struct ChecklistTestView {
    let initialSelection: Set<String>
    let disabledIDs: Set<String>
    let internalQuery: Bool
    let writePolicy: ChecklistWritePolicy
    let longList: Bool
    @State private var selection: Set<String>
    @State private var query = ""
    @State private var revision = 0
    @State private var disabledBeta = false
    @State private var lightTheme = false
    @State private var barrier = 0
    @State private var quitCount = 0

    init(initialSelection: Set<String>, disabledIDs: Set<String>, internalQuery: Bool,
         writePolicy: ChecklistWritePolicy, longList: Bool) {
        self.initialSelection = initialSelection
        self.disabledIDs = disabledIDs
        self.internalQuery = internalQuery
        self.writePolicy = writePolicy
        self.longList = longList
        _selection = State(wrappedValue: initialSelection)
    }

    private var items: [ChecklistItem] {
        if longList {
            return (0..<24).map { ChecklistItem(id: String($0), name: "Option \($0 < 10 ? "0" : "")\($0)") }
        }
        let all = ChecklistItem.fixtures
        switch revision {
        case 1: return [all[3], all[2], all[1]]
        case 2: return []
        case 3: return [all[2], all[0], all[3], all[1]]
        default: return all
        }
    }

    private var queryBinding: Binding<String>? {
        if internalQuery { return nil }
        let storage = $query
        switch writePolicy {
        case .ordinary: return $query
        case .constant: return .constant("qu")
        case .transformed: return Binding(get: { storage.wrappedValue }, set: { storage.wrappedValue = $0.lowercased() })
        }
    }

    private var selectionBinding: Binding<Set<String>> {
        let storage = $selection
        switch writePolicy {
        case .ordinary: return $selection
        case .constant: return .constant(initialSelection)
        case .transformed: return Binding(get: { storage.wrappedValue }, set: { storage.wrappedValue = $0.subtracting(["q"]) })
        }
    }
}

extension ChecklistTestView: View {
    var body: some View {
        let unavailable = disabledIDs.union(disabledBeta ? ["b"] : [])
        VStack(alignment: .leading, spacing: 0) {
            SearchableChecklist(items, selection: selectionBinding, query: queryBinding,
                                searchText: \.name, isEnabled: { !unavailable.contains($0.id) }) { Text($0.name) }
            .onResultKeyPress { press in
                guard press == KeyPress(.character("q")) else { return .ignored }
                quitCount += 1
                return .handled
            }
            // Keep the shortcut and native storage through a later filter copy.
            .filtering(.fuzzy)
            Text("S=\(selection.isEmpty ? "-" : selection.sorted().joined(separator: ","))")
            Text("Revision=\(revision) Barrier=\(barrier)")
            Text("Theme=\(lightTheme ? "light" : "dark") Quit=\(quitCount)")
        }
        .chioTheme(lightTheme ? .light : .default)
        .onKeyPress { press in
            guard press.modifiers == .ctrl else { return .ignored }
            switch press.key {
            case .character("b"): barrier += 1
            case .character("d"): revision = (revision + 1) % 4
            case .character("e"): disabledBeta.toggle()
            case .character("t"): lightTheme.toggle()
            case .character("x"): selection = ["a", "q"]
            default: return .ignored
            }
            return .handled
        }
    }
}

@MainActor
private func withChecklistScene(
    selection: Set<String> = [], disabledIDs: Set<String> = [], internalQuery: Bool = false,
    writePolicy: ChecklistWritePolicy = .ordinary, longList: Bool = false, height: Int = 20,
    perform: @MainActor (HostedSceneSession, HostedRasterSurface, HostedFrameRecorder) async throws -> Void
) async throws {
    let recorder = HostedFrameRecorder()
    let surface = HostedRasterSurface(surfaceSize: .init(width: 60, height: height), appearance: .fallback,
                                      onFrame: { recorder.receive($0) })
    let app = ChecklistTestApp(selection: selection, disabledIDs: disabledIDs, internalQuery: internalQuery,
                               writePolicy: writePolicy, longList: longList)
    let session = try HostedSceneSession(for: app, sceneID: "checklist-tests", surface: surface)
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
    var checklistSearchFocused: Bool {
        semantics.accessibilityNodes.contains { $0.identity == focusedIdentity && $0.role == .textField }
    }

    func checklistRowFocused(_ label: String) -> Bool {
        semantics.focusRegions.contains {
            $0.identity == focusedIdentity && $0.focusInteractions == .activate
        } && checklistRow(label)?.contains("▌") == true
    }

    func checklistQuery(_ value: String) -> Bool {
        semantics.accessibilityNodes.contains { $0.role == .textField && $0.control?.value == .text(value) }
    }

    func checklistContains(_ text: String) -> Bool { raster.lines.contains { $0.contains(text) } }
    func checklistRow(_ label: String) -> String? { raster.lines.first { $0.contains(label) } }
}
