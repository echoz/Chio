import Chio
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct ChioDisclosureGroupStyleTests {
    @Test("Disclosure labels and protected content share the theme at narrow widths",
          arguments: [6, 18, 36], [ChioTheme.default, .light, disclosureTestTheme])
    func raster(width: Int, theme: ChioTheme) throws {
        let closed = DefaultRenderer().render(
            DisclosureGroup("Details", isExpanded: .constant(false)) { Text("Protected body") }
                .background(theme.colors.selectedSurface)
                .chioTheme(theme),
            proposal: ProposedViewSize(width: width, height: 5)
        )
        let opened = DefaultRenderer().render(
            DisclosureGroup("Details", isExpanded: .constant(true)) { Text("Body") }
                .background(theme.colors.selectedSurface)
                .chioTheme(theme),
            proposal: ProposedViewSize(width: width, height: 5)
        )
        #expect(!closed.rasterSurface.lines.joined().contains("Protected body"))
        let closedGlyph = try #require(closed.rasterSurface.cells.flatMap { $0 }.first { $0.character == "▸" })
        let openGlyph = try #require(opened.rasterSurface.cells.flatMap { $0 }.first { $0.character == "▾" })
        #expect(closedGlyph.style?.foregroundColor == theme.colors.mutedText)
        #expect(openGlyph.style?.foregroundColor == theme.colors.accent)
        #expect(closed.rasterSurface.cells[0].allSatisfy { $0.style?.backgroundColor == theme.colors.selectedSurface })
        #expect(opened.rasterSurface.lines[1].hasPrefix("    Bo"))
        let node = try #require(closed.semanticSnapshot.accessibilityNodes.first { $0.role == .disclosureGroup })
        #expect(node.label == "Details")
        #expect(closed.rasterSurface.lines[0].filter { $0 == "▸" }.count == 1)
    }

    @Test("Disabled disclosure keeps its expansion and removes native focus", arguments: [false, true])
    func disabled(expanded: Bool) throws {
        let rendered = DefaultRenderer().render(
            DisclosureGroup("Unavailable", isExpanded: .constant(expanded)) { Text("Body") }
                .disabled(true)
                .chioTheme(.default),
            proposal: ProposedViewSize(width: 24, height: 5)
        )
        let node = try #require(rendered.semanticSnapshot.accessibilityNodes.first { $0.role == .disclosureGroup })
        #expect(!node.isEnabled)
        #expect(rendered.semanticSnapshot.focusRegions.isEmpty)
        #expect(rendered.rasterSurface.lines.joined().contains("Body") == expanded)
        #expect(!rendered.rasterSurface.lines.joined().contains("▌"))
    }

    @Test("Multiple authored children stack vertically while explicit rows keep their own layout")
    func contentLayout() {
        let lines = DefaultRenderer().render(
            DisclosureGroup("Details", isExpanded: .constant(true)) {
                Text("First")
                Text("Second")
                HStack(spacing: 1) { Text("Third"); Text("row") }
            }.chioTheme(.default),
            proposal: ProposedViewSize(width: 24, height: 6)
        ).rasterSurface.lines
        #expect(lines[0].contains("▾ Details"))
        #expect(lines[1].hasPrefix("    First"))
        #expect(lines[2].hasPrefix("    Second"))
        #expect(lines[3].hasPrefix("    Third row"))
    }

    @Test("Native activation and pointer routing keep nested application-owned values distinct")
    func nestedInteraction() async throws {
        try await withDisclosureScene { session, _, recorder in
            let initial = try await recorder.wait(description: "Parent acquires native disclosure focus") {
                $0.disclosureFocused("Parent") && $0.disclosureStatus("O=0 I=0 W=0 N=0 M=0")
            }
            self.expectHeaderPaint(initial, label: "Parent", theme: disclosureTestTheme, active: true)
            session.send(.key(.return))
            let parentOpen = try await recorder.wait(after: initial.sequence, description: "Return reveals the child disclosure") {
                $0.disclosureFocused("Parent") && $0.disclosureStatus("O=1 I=0 W=1 N=0 M=0")
                    && $0.semantics.accessibilityNodes.contains { $0.label == "Child" && $0.role == .disclosureGroup }
            }
            self.expectHeaderPaint(parentOpen, label: "Child", theme: disclosureTestTheme, active: false)
            session.send(.key(.tab))
            let child = try await recorder.wait(after: parentOpen.sequence, description: "Tab reaches the native child focus stop") {
                $0.disclosureFocused("Child")
            }
            session.send(.key(.space))
            let childOpen = try await recorder.wait(after: child.sequence, description: "Space reveals nested content without collapsing Parent") {
                $0.disclosureFocused("Child") && $0.disclosureStatus("O=1 I=1 W=1 N=0 M=0")
            }
            session.send(.key(.tab))
            let button = try await recorder.wait(after: childOpen.sequence, description: "Tab reaches the authored nested button") {
                $0.disclosureControlFocused("Increment")
            }
            session.send(.key(.return))
            let activated = try await recorder.wait(after: button.sequence, description: "nested button updates its enclosing application state") {
                $0.disclosureStatus("O=1 I=1 W=1 N=1 M=0")
            }
            let textRow = try #require(activated.raster.lines.firstIndex { $0.contains("Passive body") })
            session.send(.mouse(MouseEvent(kind: .down(.primary), location: .cellFallback(CellPoint(x: 8, y: textRow)))))
            session.send(.mouse(MouseEvent(kind: .up(.primary), location: .cellFallback(CellPoint(x: 8, y: textRow)))))
            // A queued app-owned marker provides an observable barrier after a content click that changes no value.
            session.send(.key(.character("m"), modifiers: .ctrl))
            let contentClick = try await recorder.wait(after: activated.sequence, description: "plain content click leaves both disclosures expanded") {
                $0.disclosureStatus("O=1 I=1 W=1 N=1 M=1")
            }
            let parent = try #require(contentClick.semantics.accessibilityNodes.first { $0.label == "Parent" && $0.role == .disclosureGroup })
            let headerPoint = CellPoint(x: parent.rect.origin.x + 4, y: parent.rect.origin.y)
            session.send([
                .mouse(MouseEvent(kind: .down(.primary), location: .cellFallback(headerPoint))),
                .mouse(MouseEvent(kind: .up(.primary), location: .cellFallback(headerPoint))),
            ])
            let collapsed = try await recorder.wait(after: contentClick.sequence, description: "only the native header route collapses Parent") {
                $0.disclosureStatus("O=0 I=1 W=2 N=1 M=1") && $0.disclosureFocused("Parent")
                    && !$0.semantics.accessibilityNodes.contains { $0.label == "Child" }
            }
            session.send(.key(.return))
            let restored = try await recorder.wait(after: collapsed.sequence, description: "application-owned nested expansion and count survive parent collapse") {
                $0.disclosureStatus("O=1 I=1 W=3 N=1 M=1")
                    && $0.raster.lines.contains { $0.contains("Passive body") }
            }
            #expect(restored.focusedIdentity == initial.focusedIdentity)
        }
    }

    @Test("Rejected expansion writes use the retained binding and preserve native focus through theme and resize",
          arguments: [false, true])
    func rejectedBinding(suppressed: Bool) async throws {
        try await withDisclosureScene(rejectsExpansion: true, suppressed: suppressed) { session, surface, recorder in
            let initial = try await recorder.wait(description: "rejected-binding Parent focus") {
                $0.disclosureFocused("Parent") && $0.disclosureStatus("O=0 I=0 W=0 N=0 M=0")
            }
            self.expectHeaderPaint(initial, label: "Parent", theme: disclosureTestTheme, active: !suppressed)
            session.send([.key(.space), .key(.space), .key(.return)])
            let rejected = try await recorder.wait(after: initial.sequence, description: "each rapid activation attempts expansion from the retained false value") {
                $0.disclosureStatus("O=0 I=0 W=3 N=0 M=0") && $0.disclosureFocused("Parent")
            }
            #expect(!rejected.semantics.accessibilityNodes.contains { $0.label == "Child" })
            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(after: rejected.sequence, description: "theme keeps rejected expansion and the native identity") {
                $0.disclosureFocused("Parent") && $0.raster.lines[1].contains("light")
                    && $0.disclosureStatus("O=0 I=0 W=3 N=0 M=0")
            }
            #expect(themed.focusedIdentity == initial.focusedIdentity)
            self.expectHeaderPaint(themed, label: "Parent", theme: .light, active: !suppressed)
            surface.updateSurfaceSize(CellSize(width: 18, height: 14))
            session.requestSurfaceRefresh()
            let resized = try await recorder.wait(after: themed.sequence, description: "compact rendering preserves native focus and the rejected binding") {
                $0.raster.size.width == 18 && $0.disclosureFocused("Parent")
                    && $0.raster.lines[0].hasPrefix("O=0 I=0 W=3")
            }
            #expect(resized.focusedIdentity == initial.focusedIdentity)
            session.send(.key(.return))
            _ = try await recorder.wait(after: resized.sequence, description: "native activation remains available after suppressed focus and resize") {
                $0.raster.lines[0].hasPrefix("O=0 I=0 W=4") && $0.disclosureFocused("Parent")
            }
        }
    }

    private func expectHeaderPaint(_ frame: SemanticHostFrame, label: String, theme: ChioTheme, active: Bool) {
        guard let node = frame.semantics.accessibilityNodes.first(where: { $0.role == .disclosureGroup && $0.label == label }) else {
            Issue.record("Missing disclosure \(label)")
            return
        }
        let row = frame.raster.cells[node.rect.origin.y]
        let rail = row[node.rect.origin.x]
        #expect(rail.character == (active ? "▌" : " "))
        if active { #expect(rail.style?.foregroundColor == theme.colors.accent) }
        #expect(rail.style?.backgroundColor == (active ? theme.colors.selectedSurface : theme.colors.surface))
    }
}

private let disclosureTestTheme = ChioTheme.default.replacing(colors: ChioTheme.default.colors.replacing(
    accent: Color(hexRGB: 0x123456), mutedText: Color(hexRGB: 0x345678),
    selectedSurface: Color(hexRGB: 0x654321)
))

@MainActor
private func withDisclosureScene(
    rejectsExpansion: Bool = false,
    suppressed: Bool = false,
    perform: (HostedSceneSession, HostedRasterSurface, HostedFrameRecorder) async throws -> Void
) async throws {
    let recorder = HostedFrameRecorder()
    let surface = HostedRasterSurface(surfaceSize: CellSize(width: 40, height: 14), appearance: .fallback,
                                      onFrame: { recorder.receive($0) })
    let session = try HostedSceneSession(for: DisclosureStyleTestApp(rejectsExpansion: rejectsExpansion, suppressed: suppressed),
                                        sceneID: "disclosure-style", surface: surface)
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

private struct DisclosureStyleTestApp {
    let rejectsExpansion: Bool
    let suppressed: Bool
    nonisolated init() { rejectsExpansion = false; suppressed = false }
    nonisolated init(rejectsExpansion: Bool, suppressed: Bool) {
        self.rejectsExpansion = rejectsExpansion
        self.suppressed = suppressed
    }
}

extension DisclosureStyleTestApp: App {
    var body: some Scene {
        WindowGroup(id: "disclosure-style") {
            DisclosureStyleTestView(rejectsExpansion: rejectsExpansion, suppressed: suppressed)
        }.exitOnKeys([])
    }
}

@MainActor
private struct DisclosureStyleTestView {
    let rejectsExpansion: Bool
    let suppressed: Bool
    @State private var outer = false
    @State private var inner = false
    @State private var writes = 0
    @State private var increments = 0
    @State private var marker = 0
    @State private var light = false
    @FocusState private var reading: Bool

    private var expansion: Binding<Bool> {
        let retained = $outer
        let attempted = $writes
        let rejects = rejectsExpansion
        return Binding(get: { retained.wrappedValue }, set: { next in
            attempted.wrappedValue += 1
            if !rejects { retained.wrappedValue = next }
        })
    }
}

extension DisclosureStyleTestView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("O=\(outer ? 1 : 0) I=\(inner ? 1 : 0) W=\(writes) N=\(increments) M=\(marker)")
            Text(light ? "light" : "custom")
            DisclosureGroup("Parent", isExpanded: expansion) {
                DisclosureGroup("Child", isExpanded: $inner) {
                    VStack(alignment: .leading, spacing: 0) {
                        Button("Increment") { increments += 1 }
                        Text("Passive body")
                    }
                }
            }
            .focused($reading)
            .focusEffectDisabled(suppressed)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .chioTheme(light ? .light : disclosureTestTheme)
        .onAppear { reading = true }
        .onKeyPress { press in
            switch press {
            case KeyPress(.character("t"), modifiers: .ctrl): light.toggle(); return .handled
            case KeyPress(.character("m"), modifiers: .ctrl): marker += 1; return .handled
            default: return .ignored
            }
        }
    }
}

private extension SemanticHostFrame {
    func disclosureFocused(_ label: String) -> Bool {
        semantics.accessibilityNodes.contains {
            $0.identity == focusedIdentity && $0.label == label && $0.role == .disclosureGroup
        }
    }

    func disclosureControlFocused(_ label: String) -> Bool {
        semantics.accessibilityNodes.contains { $0.identity == focusedIdentity && $0.label == label }
    }

    func disclosureStatus(_ status: String) -> Bool { raster.lines[0].contains(status) }
}
