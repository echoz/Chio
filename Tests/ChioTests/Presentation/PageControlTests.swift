import Chio
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct PageControlTests {
    @Test("Page controls retain actions and readable summaries at compact widths",
          arguments: [20, 36, 76], [false, true])
    func compactRendering(width: Int, light: Bool) {
        let theme: ChioTheme = light ? .light : .default
        let rendered = DefaultRenderer().render(
            PageControl(pagination: .constant(Pagination(totalCount: 23, pageSize: 3)))
                .chioTheme(theme), proposal: .init(width: width, height: nil)
        )
        #expect(rendered.rasterSurface.size.width <= width)
        #expect(rendered.rasterSurface.lines.contains { $0.contains("1 / 8") })
        #expect(rendered.rasterSurface.lines.contains { $0.contains("1–3 of 23") })
        #expect(rendered.rasterSurface.cells.flatMap { $0 }.contains { $0.character == "‹" })
        #expect(rendered.rasterSurface.cells.flatMap { $0 }.contains { $0.character == "›" })
        let buttons = rendered.semanticSnapshot.accessibilityNodes.filter { $0.role == .button }
        #expect(buttons.count == 2)
        #expect(buttons.contains { $0.label == "Previous page" && !$0.isEnabled })
        #expect(buttons.contains { $0.label == "Next page" && $0.isEnabled })
    }

    @Test("Page and item summaries receive their custom semantic colors")
    func customColors() {
        let theme = ChioTheme.default.replacing(colors: ChioTheme.default.colors.replacing(
            accent: Color(hexRGB: 0x112233), secondaryText: Color(hexRGB: 0x445566),
            surface: Color(hexRGB: 0x182838), border: Color(hexRGB: 0x778899)
        ))
        let surface = DefaultRenderer().render(
            PageControl(pagination: .constant(Pagination(totalCount: 23, pageSize: 3)))
                .chioTheme(theme), proposal: .init(width: 36, height: nil)
        ).rasterSurface
        let cells = surface.cells.flatMap { $0 }
        #expect(cells.contains { $0.character == "1" && $0.style?.foregroundColor == theme.colors.accent })
        #expect(cells.contains { $0.character == "1" && $0.style?.foregroundColor == theme.colors.secondaryText })
        #expect(cells.contains { $0.character == "╭" && $0.style?.foregroundColor == theme.colors.border })
        #expect(cells.contains { $0.character == "›" && $0.style?.backgroundColor == theme.colors.surface })
    }

    @Test("Large counts keep both native buttons inside the compact allocation", arguments: [20, 36, 76])
    func largeCountRendering(width: Int) {
        let pagination = Pagination(totalCount: Int.max, pageSize: 1).movingToLastPage()
        let rendered = DefaultRenderer().render(
            PageControl(pagination: .constant(pagination)).chioTheme(.default),
            proposal: .init(width: width, height: nil)
        )
        #expect(rendered.rasterSurface.size.width <= width)
        let buttons = rendered.semanticSnapshot.accessibilityNodes.filter { $0.role == .button }
        #expect(buttons.count == 2)
        #expect(buttons.allSatisfy { $0.rect.origin.x >= 0 && $0.rect.maxX <= width })
        #expect(buttons.contains { $0.label == "Previous page" && $0.isEnabled })
        #expect(buttons.contains { $0.label == "Next page" && !$0.isEnabled })
        #expect(rendered.rasterSurface.lines.filter { !$0.trimmingPageSpaces.isEmpty }.count >= 2)
        if width == 76 {
            #expect(rendered.rasterSurface.lines.contains { $0.contains("\(Int.max) / \(Int.max)") })
            #expect(rendered.rasterSurface.lines.contains { $0.contains("\(Int.max)–\(Int.max) of \(Int.max)") })
        }
    }

    @Test("Empty and single-page collections have no native page focus stops", arguments: [0, 1, 3])
    func inertRendering(count: Int) {
        let rendered = DefaultRenderer().render(
            PageControl(pagination: .constant(Pagination(totalCount: count, pageSize: 3)))
                .chioTheme(.default), proposal: .init(width: 20, height: nil)
        )
        let buttons = rendered.semanticSnapshot.accessibilityNodes.filter { $0.role == .button }
        #expect(buttons.count == 2 && buttons.allSatisfy { !$0.isEnabled })
        #expect(buttons.allSatisfy { button in
            !rendered.semanticSnapshot.focusRegions.contains { $0.identity == button.identity }
        })
        #expect(rendered.rasterSurface.lines.contains { $0.contains(count == 0 ? "No pages" : "1 / 1") })
        #expect(rendered.rasterSurface.lines.contains { $0.contains(count == 0 ? "0 items" : "1–\(count) of \(count)") })
    }

    @Test("Return and Space activate native buttons and Tab reaches adjacent editing")
    func nativeActivationAndEditing() async throws {
        try await withPageControlScene { session, _, recorder in
            _ = try await recorder.wait(description: "Previous page has native initial focus") {
                $0.pageButtonFocused("Previous page") && $0.pageState(index: 1, total: 23)
            }
            session.send(.key(.return))
            _ = try await recorder.wait(description: "Return reaches page one and native focus skips disabled Previous") {
                $0.pageState(index: 0, total: 23) && $0.pageButtonFocused("Next page")
            }
            session.send(.key(.space))
            _ = try await recorder.wait(description: "Space activates Next through its native action") {
                $0.pageState(index: 1, total: 23) && $0.pageButtonFocused("Next page")
            }
            session.send(.key(.tab, modifiers: .shift))
            _ = try await recorder.wait(description: "Shift-Tab reaches Previous") { $0.pageButtonFocused("Previous page") }
            session.send(.key(.tab))
            _ = try await recorder.wait(description: "Tab returns to Next") { $0.pageButtonFocused("Next page") }
            session.send(.key(.tab))
            let editor = try await recorder.wait(description: "Tab leaves page controls for the native text field") { $0.pageEditorFocused }
            session.send([.key(.end), .key(.arrowLeft), .key(.character("X")), .key(.character("b"), modifiers: .ctrl)])
            let edited = try await recorder.wait(after: editor.sequence, description: "editor arrows edit text without paging") {
                $0.pageContains("B=1") && $0.pageEditorValue == "abXc"
            }
            #expect(edited.pageEditorFocused)
            #expect(edited.pageState(index: 1, total: 23))
            #expect(edited.pageContains("W=2"))
        }
    }

    @Test("Fast arrow batches read the retained binding and stop at boundaries")
    func arrowBatches() async throws {
        try await withPageControlScene { session, _, recorder in
            let initial = try await recorder.wait(description: "native paging focus before batched input") {
                $0.pageButtonFocused("Previous page") && $0.pageState(index: 1, total: 23)
            }
            session.send(Array(repeating: .key(.arrowRight), count: 20) + [.key(.character("b"), modifiers: .ctrl)])
            let last = try await recorder.wait(after: initial.sequence, description: "all Right keys reach the final page without wrapping") {
                $0.pageContains("B=1") && $0.pageState(index: 7, total: 23)
            }
            #expect(last.pageContains("W=6"))
            #expect(last.pageContains("22–23 of 23"))
            session.send(Array(repeating: .key(.arrowLeft), count: 20) + [.key(.character("b"), modifiers: .ctrl)])
            let first = try await recorder.wait(after: last.sequence, description: "all Left keys reach the first page and disabled Previous loses focus") {
                $0.pageContains("B=2") && $0.pageState(index: 0, total: 23) && $0.pageButtonFocused("Next page")
            }
            #expect(first.pageContains("W=13"))
            session.send([.key(.end), .key(.arrowLeft), .key(.home), .key(.arrowRight),
                          .key(.character("b"), modifiers: .ctrl)])
            _ = try await recorder.wait(after: first.sequence, description: "Home and End compose with arrows in one input batch") {
                $0.pageContains("B=3") && $0.pageState(index: 1, total: 23)
            }
        }
    }

    @Test("Rejected writes retain the displayed page without optimistic navigation")
    func rejectedBinding() async throws {
        try await withPageControlScene(initial: Pagination(totalCount: 23, pageSize: 3), policy: .reject) { session, _, recorder in
            let initial = try await recorder.wait(description: "rejected-write fixture has Next focus") { $0.pageButtonFocused("Next page") }
            session.send([.key(.arrowRight), .key(.arrowRight), .key(.return),
                          .key(.character("b"), modifiers: .ctrl)])
            let rejected = try await recorder.wait(after: initial.sequence, description: "three rejected writes were dispatched") {
                $0.pageContains("B=1") && $0.pageContains("W=3")
            }
            #expect(rejected.pageState(index: 0, total: 23))
            #expect(rejected.pageContains("1 / 8") && rejected.pageContains("1–3 of 23"))
            #expect(rejected.pageButtonFocused("Next page"))
        }
    }

    @Test("Transformed writes determine the next transition in a fast input batch")
    func transformedBinding() async throws {
        try await withPageControlScene(initial: Pagination(totalCount: 23, pageSize: 3), policy: .skipForward) { session, _, recorder in
            let initial = try await recorder.wait(description: "transformed-write fixture has Next focus") { $0.pageButtonFocused("Next page") }
            session.send([.key(.arrowRight), .key(.arrowRight), .key(.arrowRight),
                          .key(.character("b"), modifiers: .ctrl)])
            let transformed = try await recorder.wait(after: initial.sequence, description: "each proposal starts from the transformed retained page") {
                $0.pageContains("B=1") && $0.pageContains("W=3")
            }
            #expect(transformed.pageState(index: 6, total: 23))
            #expect(transformed.pageContains("7 / 8") && transformed.pageContains("19–21 of 23"))
            session.send([.key(.arrowRight), .key(.arrowRight), .key(.character("b"), modifiers: .ctrl)])
            let bounded = try await recorder.wait(after: transformed.sequence, description: "transformed endpoint does not cause an extra write") {
                $0.pageContains("B=2") && $0.pageState(index: 7, total: 23)
            }
            #expect(bounded.pageContains("W=4"))
        }
    }

    @Test("External count changes are authoritative before the next page action")
    func externalCounts() async throws {
        let initial = Pagination(totalCount: 23, pageSize: 3).movingToLastPage()
        try await withPageControlScene(initial: initial) { session, _, recorder in
            let last = try await recorder.wait(description: "last page has native Previous focus") {
                $0.pageButtonFocused("Previous page") && $0.pageState(index: 7, total: 23)
            }
            session.send([.key(.character("s"), modifiers: .ctrl), .key(.arrowLeft),
                          .key(.character("b"), modifiers: .ctrl)])
            let shrunk = try await recorder.wait(after: last.sequence, description: "shrink clamps before the next Left transition") {
                $0.pageContains("B=1") && $0.pageState(index: 0, total: 5)
            }
            #expect(shrunk.pageContains("1 / 2") && shrunk.pageContains("1–3 of 5"))
            _ = try await recorder.wait(description: "native Next is enabled after shrinking to page one") { $0.pageButtonFocused("Next page") }
            session.send([.key(.character("g"), modifiers: .ctrl), .key(.end), .key(.arrowLeft),
                          .key(.character("b"), modifiers: .ctrl)])
            let grown = try await recorder.wait(after: shrunk.sequence, description: "End reads the increased count before another Left transition") {
                $0.pageContains("B=2") && $0.pageState(index: 8, total: 29)
            }
            #expect(grown.pageContains("9 / 10") && grown.pageContains("25–27 of 29"))
            session.send(.key(.character("e"), modifiers: .ctrl))
            let empty = try await recorder.wait(after: grown.sequence, description: "external empty data removes page actions from native focus") {
                $0.pageState(index: nil, total: 0) && $0.pageEditorFocused
            }
            #expect(empty.pageContains("No pages") && empty.pageContains("0 items"))
            #expect(empty.semantics.accessibilityNodes.filter { $0.role == .button && ($0.label == "Previous page" || $0.label == "Next page") }
                .allSatisfy { !$0.isEnabled })
        }
    }

    @Test("Theme and resize preserve page values and an enabled native focus identity")
    func themeAndResize() async throws {
        try await withPageControlScene { session, surface, recorder in
            let initial = try await recorder.wait(description: "enabled Previous focus before theme changes") { $0.pageButtonFocused("Previous page") }
            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(after: initial.sequence, description: "light theme retains the page and native focus") {
                $0.pageContains("Light=true") && $0.pageButtonFocused("Previous page")
            }
            #expect(themed.focusedIdentity == initial.focusedIdentity)
            #expect(themed.pageState(index: 1, total: 23))
            #expect(themed.raster.cells.flatMap { $0 }.contains {
                $0.character == "2" && $0.style?.foregroundColor == ChioTheme.light.colors.accent
            })
            surface.updateSurfaceSize(.init(width: 20, height: 18))
            session.requestSurfaceRefresh()
            let narrow = try await recorder.wait(after: themed.sequence, description: "compact resize retains native Previous focus") {
                $0.raster.size.width == 20 && $0.pageButtonFocused("Previous page")
            }
            #expect(narrow.focusedIdentity == initial.focusedIdentity)
            #expect(narrow.pageState(index: 1, total: 23))
            #expect(narrow.pageContains("2 / 8") && narrow.pageContains("4–6 of 23"))
            session.send(.key(.arrowRight))
            _ = try await recorder.wait(after: narrow.sequence, description: "navigation still works after compact resize") {
                $0.pageState(index: 2, total: 23) && $0.pageButtonFocused("Previous page")
            }
        }
    }

    @Test("A disabled ancestor removes native page actions and preserves the value")
    func disabledAncestor() async throws {
        try await withPageControlScene { session, _, recorder in
            let initial = try await recorder.wait(description: "Previous focus before disabling navigation") { $0.pageButtonFocused("Previous page") }
            session.send(.key(.character("d"), modifiers: .ctrl))
            let disabled = try await recorder.wait(after: initial.sequence, description: "disabled navigation yields native focus to editing") {
                $0.pageContains("Disabled=true") && $0.pageEditorFocused
            }
            let pageButtons = disabled.semantics.accessibilityNodes.filter {
                $0.role == .button && ($0.label == "Previous page" || $0.label == "Next page")
            }
            #expect(pageButtons.count == 2 && pageButtons.allSatisfy { !$0.isEnabled })
            #expect(pageButtons.allSatisfy { button in !disabled.semantics.focusRegions.contains { $0.identity == button.identity } })
            session.send([.key(.arrowRight), .key(.end), .key(.character("b"), modifiers: .ctrl)])
            let unchanged = try await recorder.wait(after: disabled.sequence, description: "disabled page navigation never writes its binding") {
                $0.pageContains("B=1")
            }
            #expect(unchanged.pageState(index: 1, total: 23) && unchanged.pageContains("W=0"))
            session.send(.key(.character("d"), modifiers: .ctrl))
            let enabled = try await recorder.wait(after: unchanged.sequence, description: "page actions return to native focus participation") {
                $0.pageContains("Disabled=false")
            }
            #expect(enabled.semantics.accessibilityNodes.filter { $0.role == .button && ($0.label == "Previous page" || $0.label == "Next page") }
                .allSatisfy { $0.isEnabled })
            session.send(.key(.tab, modifiers: .shift))
            _ = try await recorder.wait(description: "Shift-Tab reaches reenabled Next") { $0.pageButtonFocused("Next page") }
            session.send(.key(.return))
            _ = try await recorder.wait(description: "reenabled native activation advances one page") { $0.pageState(index: 2, total: 23) }
        }
    }
}

private enum PageWritePolicy: Sendable {
    case ordinary, reject, skipForward
}

private struct PageControlTestApp {
    let initial: Pagination
    let policy: PageWritePolicy

    nonisolated init() {
        initial = Pagination(totalCount: 23, pageSize: 3).movingToNextPage()
        policy = .ordinary
    }

    nonisolated init(initial: Pagination, policy: PageWritePolicy) {
        self.initial = initial
        self.policy = policy
    }
}

extension PageControlTestApp: App {
    var body: some Scene {
        WindowGroup(id: "page-control-tests") { PageControlTestView(initial: initial, policy: policy) }.exitOnKeys([])
    }
}

@MainActor
private struct PageControlTestView {
    let policy: PageWritePolicy
    @State private var pagination: Pagination
    @State private var text = "abc"
    @State private var writes = 0
    @State private var barrier = 0
    @State private var light = false
    @State private var disabled = false

    init(initial: Pagination, policy: PageWritePolicy) {
        self.policy = policy
        _pagination = State(wrappedValue: initial)
    }

    private var controlledPagination: Binding<Pagination> {
        let storage = $pagination
        let writeCount = $writes
        return Binding(get: { storage.wrappedValue }, set: { proposed in
            writeCount.wrappedValue += 1
            switch policy {
            case .ordinary: storage.wrappedValue = proposed
            case .reject: break
            case .skipForward: storage.wrappedValue = proposed.movingToNextPage()
            }
        })
    }
}

extension PageControlTestView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageControl(pagination: controlledPagination).disabled(disabled)
            TextField("Adjacent editor", text: $text)
            Button("After") {}
            Text("P=\(pagination.pageIndex.map(String.init) ?? "nil") N=\(pagination.totalCount)")
            Text("W=\(writes) B=\(barrier)")
            Text("Light=\(light)")
            Text("Disabled=\(disabled)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .chioTheme(light ? .light : .default)
        .onKeyPress { press in
            guard press.modifiers == .ctrl else { return .ignored }
            switch press.key {
            case .character("b"): barrier += 1
            case .character("s"): pagination = pagination.updatingTotalCount(to: 5)
            case .character("g"): pagination = pagination.updatingTotalCount(to: 29)
            case .character("e"): pagination = pagination.updatingTotalCount(to: 0)
            case .character("t"): light.toggle()
            case .character("d"): disabled.toggle()
            default: return .ignored
            }
            return .handled
        }
    }
}

@MainActor
private func withPageControlScene(
    initial: Pagination = Pagination(totalCount: 23, pageSize: 3).movingToNextPage(),
    policy: PageWritePolicy = .ordinary,
    perform: @MainActor (HostedSceneSession, HostedRasterSurface, HostedFrameRecorder) async throws -> Void
) async throws {
    let recorder = HostedFrameRecorder()
    let surface = HostedRasterSurface(surfaceSize: .init(width: 76, height: 18), appearance: .fallback,
                                      onFrame: { recorder.receive($0) })
    let session = try HostedSceneSession(for: PageControlTestApp(initial: initial, policy: policy),
                                        sceneID: "page-control-tests", surface: surface)
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
    func pageContains(_ text: String) -> Bool { raster.lines.contains { $0.contains(text) } }

    func pageState(index: Int?, total: Int) -> Bool {
        pageContains("P=\(index.map(String.init) ?? "nil") N=\(total)")
    }

    func pageButtonFocused(_ label: String) -> Bool {
        semantics.accessibilityNodes.contains { $0.role == .button && $0.label == label && $0.identity == focusedIdentity }
    }

    var pageEditorFocused: Bool {
        semantics.accessibilityNodes.contains { $0.role == .textField && $0.identity == focusedIdentity }
    }

    var pageEditorValue: String? {
        guard let value = semantics.accessibilityNodes.first(where: { $0.role == .textField })?.control?.value,
              case .text(let text) = value else { return nil }
        return text
    }
}

private extension String {
    var trimmingPageSpaces: String { String(reversed().drop(while: { $0 == " " }).reversed()) }
}
