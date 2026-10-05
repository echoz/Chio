import Chio
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct MarkdownLinkTests {
    @Test("Interactive links retain Unicode wrapping, mixed styles and one native focus stop per label",
          arguments: [12, 38], [false, true])
    func rendering(width: Int, light: Bool) {
        let theme: ChioTheme = light ? .light : .default
        let rendered = DefaultRenderer().render(
            MarkdownView(MarkdownDocument("Before [**你好** *café* `code`](../guide#intro)[again](../guide#intro) after."),
                         openLink: OpenLinkAction { _ in Issue.record("Rendering activated a link"); return false })
                .chioTheme(theme),
            proposal: .init(width: width, height: 20)
        )
        #expect(rendered.rasterSurface.size.width <= width)
        let cells = rendered.rasterSurface.cells.flatMap { $0 }
        #expect(cells.contains { $0.character == "你" && $0.style?.emphasis.contains(.bold) == true })
        #expect(cells.contains { $0.character == "c" && $0.style?.emphasis.contains(.italic) == true })
        #expect(cells.filter { $0.hyperlink != nil }.allSatisfy {
            $0.hyperlink == "../guide#intro" && $0.style?.foregroundColor == theme.colors.accent
        })
        #expect(rendered.semanticSnapshot.focusRegions.filter { $0.focusInteractions == .activate }.count == 2)
        #expect(!rendered.rasterSurface.lines.joined().contains("../guide"))
    }

    @Test("Passive documents retain destinations and never acquire link interaction")
    func passive() {
        let rendered = DefaultRenderer().render(
            MarkdownView(MarkdownDocument("**[Docs](guide.md)** ![Chart](plot.png) [empty]()"))
                .openLinkAction(OpenLinkAction { _ in Issue.record("Passive document activated"); return true })
                .chioTheme(.default),
            proposal: .init(width: 80, height: 5)
        )
        #expect(rendered.rasterSurface.lines.joined().contains("Docs (guide.md) Chart (plot.png) empty"))
        #expect(rendered.rasterSurface.cells.flatMap { $0 }.allSatisfy { $0.hyperlink == nil })
        #expect(rendered.semanticSnapshot.focusRegions.isEmpty)
        #expect(rendered.rasterSurface.cells[0][6].style?.emphasis.contains(.bold) == true)
    }

    @Test("Tables expose body links while plain native headers keep readable destinations")
    func table() {
        let rendered = DefaultRenderer().render(
            MarkdownView(MarkdownDocument("| [Header](head.md) |\n| --- |\n| [Body](body.md) |"),
                         openLink: OpenLinkAction { _ in false }).chioTheme(.default),
            proposal: .init(width: 40, height: 15)
        )
        #expect(rendered.rasterSurface.lines.joined().contains("Header (head.md)"))
        let destinations = Set(rendered.rasterSurface.cells.flatMap { $0 }.compactMap(\.hyperlink))
        #expect(destinations == ["body.md"])
        #expect(rendered.semanticSnapshot.focusRegions.filter { $0.focusInteractions == .activate }.count == 1)
    }

    @Test("Empty destinations, images and disabled documents cannot create active focus stops")
    func disabled() {
        for source in ["[Empty]() ![Image](plot.png) `<https://example.com>`", "[Disabled](guide.md)"] {
            let rendered = DefaultRenderer().render(
                MarkdownView(MarkdownDocument(source), openLink: OpenLinkAction { _ in false })
                    .disabled(true).chioTheme(.default),
                proposal: .init(width: 70, height: 5)
            )
            #expect(rendered.semanticSnapshot.focusRegions.isEmpty)
        }
    }

    @Test("Image alt-text links remain passive while an explicitly linked image has one outer action")
    func imageLinks() {
        let rendered = DefaultRenderer().render(
            MarkdownView(MarkdownDocument("![foo [bar](/url)](/url2) [![chart](plot.png)](guide.md)"),
                         openLink: OpenLinkAction { _ in false }).chioTheme(.default),
            proposal: .init(width: 80, height: 5)
        )
        #expect(rendered.rasterSurface.lines.joined().contains("foo bar (/url) (/url2) chart (plot.png)"))
        #expect(Set(rendered.rasterSurface.cells.flatMap { $0 }.compactMap(\.hyperlink)) == ["guide.md"])
        #expect(rendered.semanticSnapshot.focusRegions.filter { $0.focusInteractions == .activate }.count == 1)
    }

    @Test("Native links dispatch once, retain focus through theme and wrapping, and respect disabled/focus effects")
    func interaction() async throws {
        let recorder = HostedFrameRecorder()
        let surface = HostedRasterSurface(surfaceSize: .init(width: 48, height: 16), appearance: .fallback,
                                          onFrame: { recorder.receive($0) })
        let session = try HostedSceneSession(for: LinkTestApp(), sceneID: "links", surface: surface)
        let run = Task { try await session.start() }
        defer { session.stop() }
        do {
            let initial = try await recorder.wait(description: "passive reader focus") {
                $0.raster.lines.contains { $0.contains("Calls=0 Outer=0") } && self.focusedDestination($0) == nil
                    && $0.focusedIdentity != nil
            }
            session.send(.key(.tab))
            let focused = try await recorder.wait(after: initial.sequence, description: "first inline link focus") {
                self.focusedDestination($0) == "guide.md"
            }
            #expect(linkCells(focused).contains { $0.style?.backgroundColor == ChioTheme.default.colors.selectedSurface })
            session.send(.key(.return))
            let opened = try await recorder.wait(after: focused.sequence, description: "exact app destination once") {
                $0.raster.lines.contains { $0.contains("Calls=1 Outer=0") }
                    && $0.raster.lines.contains { $0.contains("Open=guide.md") }
            }
            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(after: opened.sequence, description: "theme keeps inline identity") {
                $0.raster.lines.contains { $0.contains("Light=true") }
            }
            #expect(themed.focusedIdentity == focused.focusedIdentity)
            #expect(linkCells(themed).contains { $0.style?.backgroundColor == ChioTheme.light.colors.selectedSurface })
            surface.updateSurfaceSize(.init(width: 24, height: 18))
            session.requestSurfaceRefresh()
            let narrow = try await recorder.wait(after: themed.sequence, description: "wrapped label keeps native focus") {
                $0.raster.size.width == 24 && self.focusedDestination($0) == "guide.md"
            }
            #expect(narrow.focusedIdentity == focused.focusedIdentity)
            session.send(.key(.character("f"), modifiers: .ctrl))
            let suppressed = try await recorder.wait(after: narrow.sequence, description: "focus effect disabled") {
                $0.raster.lines.contains { $0.contains("Effect=false") }
            }
            #expect(suppressed.focusedIdentity == focused.focusedIdentity)
            #expect(!linkCells(suppressed).contains { $0.style?.backgroundColor == ChioTheme.light.colors.selectedSurface })
            session.send(.key(.space))
            let second = try await recorder.wait(after: suppressed.sequence, description: "Space activates native link") {
                $0.raster.lines.contains { $0.contains("Calls=2 Outer=0") }
            }
            session.send(.key(.tab))
            let rejected = try await recorder.wait(after: second.sequence, description: "next destination has its own focus stop") {
                self.focusedDestination($0) == "custom:reject"
            }
            session.send(.key(.return))
            let handled = try await recorder.wait(after: rejected.sequence, description: "rejection stays with the app action") {
                $0.raster.lines.contains { $0.contains("Calls=3 Outer=0") }
                    && $0.raster.lines.contains { $0.contains("Open=custom:reject") }
            }
            session.send(.key(.tab, modifiers: .shift))
            let back = try await recorder.wait(after: handled.sequence, description: "Shift-Tab returns to first inline identity") {
                $0.focusedIdentity == focused.focusedIdentity
            }
            session.send(.key(.character("d"), modifiers: .ctrl))
            let disabled = try await recorder.wait(after: back.sequence, description: "disabled document removes link focus") {
                $0.raster.lines.contains { $0.contains("Enabled=false") }
                    && !$0.semantics.focusRegions.contains { $0.focusInteractions == .activate }
            }
            session.send(.key(.return))
            session.send(.key(.character("t"), modifiers: .ctrl))
            let inert = try await recorder.wait(after: disabled.sequence, description: "disabled activation stays inert") {
                $0.raster.lines.contains { $0.contains("Light=false") }
            }
            #expect(inert.raster.lines.contains { $0.contains("Calls=3 Outer=0") })
            session.stop()
            #expect(try await run.value == .inputEnded)
        } catch {
            session.stop()
            _ = await run.result
            throw error
        }
    }

    private func focusedDestination(_ frame: SemanticHostFrame) -> String? {
        guard let region = frame.semantics.focusRegions.first(where: { $0.identity == frame.focusedIdentity }),
              region.focusInteractions == .activate else { return nil }
        let origin = region.rect.origin
        return frame.raster.cells[origin.y][origin.x].hyperlink
    }

    @Test("Native table scrolling reveals and activates body links without making headers interactive")
    func tableInteraction() async throws {
        let document = MarkdownDocument("""
        | [Header](header.md) | A wide middle column | End |
        | --- | --- | --- |
        | [First](first.md) | Some wide content | [Last](last.md) |
        """)
        let recorder = HostedFrameRecorder()
        let surface = HostedRasterSurface(surfaceSize: .init(width: 30, height: 18), appearance: .fallback,
                                          onFrame: { recorder.receive($0) })
        let session = try HostedSceneSession(for: LinkTestApp(document), sceneID: "links", surface: surface)
        let run = Task { try await session.start() }
        defer { session.stop() }
        do {
            let initial = try await recorder.wait(description: "table reader ready") {
                $0.raster.lines.contains { $0.contains("Header (header.md)") } && $0.focusedIdentity != nil
            }
            session.send(.key(.tab))
            let table = try await recorder.wait(after: initial.sequence, description: "horizontal table focus") {
                $0.focusedIdentity != initial.focusedIdentity && self.focusedDestination($0) == nil
            }
            session.send(.key(.tab))
            let first = try await recorder.wait(after: table.sequence, description: "first visible table link") {
                self.focusedDestination($0) == "first.md"
            }
            session.send(.key(.return))
            let opened = try await recorder.wait(after: first.sequence, description: "body link dispatch") {
                $0.raster.lines.contains { $0.contains("Open=first.md") }
            }
            session.send(.key(.tab, modifiers: .shift))
            let back = try await recorder.wait(after: opened.sequence, description: "native table focus restored") {
                $0.focusedIdentity == table.focusedIdentity
            }
            session.send(.key(.end))
            let end = try await recorder.wait(after: back.sequence, description: "horizontal End exposes last link") {
                $0.raster.cells.flatMap { $0 }.contains { $0.hyperlink == "last.md" }
            }
            #expect(end.focusedIdentity == table.focusedIdentity)
            session.send(.key(.tab))
            let last = try await recorder.wait(after: end.sequence, description: "Tab reaches newly visible table link") {
                self.focusedDestination($0) == "last.md"
            }
            session.send(.key(.return))
            _ = try await recorder.wait(after: last.sequence, description: "last link dispatch") {
                $0.raster.lines.contains { $0.contains("Open=last.md") }
                    && $0.raster.lines.contains { $0.contains("Calls=2 Outer=0") }
            }
            session.stop()
            #expect(try await run.value == .inputEnded)
        } catch {
            session.stop()
            _ = await run.result
            throw error
        }
    }

    private func linkCells(_ frame: SemanticHostFrame) -> [RasterCell] {
        frame.raster.cells.flatMap { $0 }.filter { $0.hyperlink == "guide.md" }
    }
}

private struct LinkTestApp {
    let document: MarkdownDocument

    nonisolated init() {
        document = MarkdownDocument("Read [`long code label`](guide.md), then [reject](custom:reject).")
    }

    nonisolated init(_ document: MarkdownDocument) {
        self.document = document
    }
}

extension LinkTestApp: App {
    var body: some Scene {
        WindowGroup(id: "links") { LinkTestView(document: document) }.exitOnKeys([])
    }
}

@MainActor
private struct LinkTestView {
    @State private var calls = 0
    @State private var outer = 0
    @State private var opened = ""
    @State private var light = false
    @State private var enabled = true
    @State private var effect = true
    @FocusState private var reading: Bool
    let document: MarkdownDocument
}

extension LinkTestView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Calls=\(calls) Outer=\(outer)")
            Text("Open=\(opened)")
            Text("Light=\(light)")
            Text("Enabled=\(enabled)")
            Text("Effect=\(effect)")
            ScrollView {
                MarkdownView(document, openLink: OpenLinkAction { destination in
                    calls += 1
                    opened = destination.rawValue
                    return destination.rawValue != "custom:reject"
                })
                .disabled(!enabled)
                .focusEffectDisabled(!effect)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .focused($reading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .chioTheme(light ? .light : .default)
        .openLinkAction(OpenLinkAction { _ in outer += 1; return true })
        .onAppear { reading = true }
        .onKeyPress { press in
            switch press {
            case KeyPress(.character("t"), modifiers: .ctrl): light.toggle()
            case KeyPress(.character("d"), modifiers: .ctrl): enabled.toggle()
            case KeyPress(.character("f"), modifiers: .ctrl): effect.toggle()
            default: return .ignored
            }
            return .handled
        }
    }
}
