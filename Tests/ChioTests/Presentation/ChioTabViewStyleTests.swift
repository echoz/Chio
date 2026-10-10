import Chio
import Foundation
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct ChioTabViewStyleTests {
    @Test("Native tabs retain selected content and adapt their strip to terminal width",
          arguments: [12, 36, 76], [ChioTheme.default, .light])
    func widthAndTheme(width: Int, theme: ChioTheme) throws {
        let rendered = DefaultRenderer().render(
            TabView(selection: .constant("logs")) {
                Tab("Home", detail: "3", badge: "new", value: "home") { Text("Home body") }
                Tab("Settings", value: "settings") { Text("Settings body") }
                Tab("Logs", value: "logs") { Text("Logs body") }
            }.chioTheme(theme),
            proposal: ProposedViewSize(width: width, height: 8)
        )
        let lines = rendered.rasterSurface.lines
        #expect(lines[2].contains("Logs body"))
        #expect(!lines.joined().contains("Home body"))
        #expect(!lines.joined().contains("Settings body"))
        #expect(lines[0].contains("More") == (width == 12))
        if width > 12 {
            #expect(lines[0].contains("Home · 3 · [new]"))
            #expect(lines[0].contains("Settings"))
            let selected = try #require(rendered.rasterSurface.cells[0].first { $0.character == "L" })
            #expect(selected.style?.foregroundColor == theme.colors.accent)
            #expect(selected.style?.emphasis.contains(.bold) == true)
            #expect(selected.style?.backgroundColor == theme.colors.surface)
            #expect(rendered.rasterSurface.cells[1].contains {
                $0.character == "━" && $0.style?.foregroundColor == theme.colors.accent
            })
        } else {
            #expect(rendered.rasterSurface.cells[1].contains {
                $0.character == "━" && $0.style?.foregroundColor == theme.colors.accent
            })
        }
        #expect(rendered.semanticSnapshot.accessibilityNodes.contains { $0.role == .tabView })
    }

    @Test("Tab widths use terminal cells for wide and combining labels")
    func unicodeWidths() {
        let rendered = DefaultRenderer().render(
            TabView(selection: .constant(0)) {
                Tab("日本", value: 0) { Text("First") }
                Tab("e\u{301}", value: 1) { Text("Second") }
            }.chioTheme(.default),
            proposal: ProposedViewSize(width: 9, height: 4)
        )
        #expect(rendered.rasterSurface.lines[0].contains("日本"))
        #expect(rendered.rasterSurface.lines[0].contains("e\u{301}"))
        #expect(!rendered.rasterSurface.lines[0].contains("More"))
        #expect(rendered.rasterSurface.lines[2].contains("First"))
    }

    @Test("An overlong single tab remains selected behind a discoverable trigger")
    func overlongLabel() {
        let rendered = DefaultRenderer().render(
            TabView(selection: .constant(0)) {
                Tab("A label much wider than this terminal", value: 0) { Text("Only content") }
            }.chioTheme(.default),
            proposal: ProposedViewSize(width: 12, height: 4)
        )
        #expect(rendered.rasterSurface.lines[0].contains("More"))
        #expect(rendered.rasterSurface.lines[1].contains("━"))
        #expect(rendered.rasterSurface.lines[2].contains("Only content"))
    }

    @Test("Empty and single native tab collections render without unnecessary overflow")
    func cardinality() {
        let empty = DefaultRenderer().render(
            TabView(selection: .constant(0)) { EmptyView() }.chioTheme(.default),
            proposal: ProposedViewSize(width: 12, height: 4)
        )
        #expect(empty.rasterSurface.lines.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        let one = DefaultRenderer().render(
            TabView(selection: .constant(0)) { Tab("One", value: 0) { Text("Only") } }.chioTheme(.default),
            proposal: ProposedViewSize(width: 12, height: 4)
        )
        #expect(one.rasterSurface.lines[0].contains("One"))
        #expect(!one.rasterSurface.lines[0].contains("More"))
        #expect(one.rasterSurface.lines[2].contains("Only"))
    }

    @Test("Disabled native tabs retain their content and report unavailable semantics")
    func disabled() throws {
        let rendered = DefaultRenderer().render(
            TabView(selection: .constant("removed")) {
                Tab("One", value: "one") { Text("Fallback body") }
                Tab("Two", value: "two") { Text("Second body") }
            }.disabled(true).chioTheme(.default),
            proposal: ProposedViewSize(width: 36, height: 5)
        )
        #expect(rendered.rasterSurface.lines[2].contains("Fallback body"))
        #expect(!rendered.rasterSurface.lines.joined().contains("Second body"))
        let tabs = try #require(rendered.semanticSnapshot.accessibilityNodes.first { $0.role == .tabView })
        #expect(!tabs.isEnabled)
        #expect(!rendered.semanticSnapshot.focusRegions.contains { $0.identity == tabs.identity })
    }

    @Test("Native cursor focus differs from selection and respects suppressed focus paint", arguments: [false, true])
    func selectionAndFocus(suppressed: Bool) async throws {
        let theme = ChioTheme.default.replacing(colors: ChioTheme.default.colors.replacing(
            accent: Color(hexRGB: 0x123456), selectedSurface: Color(hexRGB: 0x654321)
        ))
        let recorder = HostedFrameRecorder()
        let surface = HostedRasterSurface(surfaceSize: CellSize(width: 36, height: 8), appearance: .fallback,
                                          onFrame: { recorder.receive($0) })
        let session = try HostedSceneSession(for: TabStyleTestApp(theme: theme, suppressed: suppressed),
                                            sceneID: "tab-style", surface: surface)
        let run = Task { try await session.start() }
        do {
            let initial = try await recorder.wait(description: "native tab strip focus") {
                $0.raster.lines.contains { $0.contains("Body 0") } && $0.focusedIdentity != nil
            }
            session.send(.key(.arrowRight))
            let moved = try await recorder.wait(after: initial.sequence, description: "focus moves independently of selection") {
                let cells = $0.raster.cells[0]
                return $0.raster.lines.contains { $0.contains("Body 0") }
                    && (suppressed || cells.contains {
                        $0.character == "1" && $0.style?.backgroundColor == theme.colors.selectedSurface
                    })
            }
            #expect(moved.raster.cells[0].contains {
                $0.character == "0" && $0.style?.foregroundColor == theme.colors.accent
            })
            #expect(moved.raster.cells[1].contains { $0.character == "━" })
            if suppressed {
                #expect(!moved.raster.cells[0].contains { $0.style?.backgroundColor == theme.colors.selectedSurface })
            }
            session.send(.key(.return))
            _ = try await recorder.wait(after: moved.sequence, description: "native Return activates cursor tab") {
                $0.raster.lines.contains { $0.contains("Body 1") }
            }
            session.stop()
            #expect(try await run.value == .inputEnded)
        } catch {
            session.stop()
            _ = await run.result
            throw error
        }
    }

    @Test("Tiny expanded tab menus leave neighboring layout cells untouched", arguments: [0, 1, 2])
    func tinyOverflow(width: Int) async throws {
        let recorder = HostedFrameRecorder()
        let surface = HostedRasterSurface(surfaceSize: CellSize(width: 30, height: 8), appearance: .fallback,
                                          onFrame: { recorder.receive($0) })
        let session = try HostedSceneSession(for: TinyTabsTestApp(width: width), sceneID: "tiny-tabs", surface: surface)
        let run = Task { try await session.start() }
        do {
            let initial = try await recorder.wait(description: "tiny strip starts focused") {
                $0.focusedIdentity != nil && $0.raster.lines[0].contains("Selected: 0")
            }
            session.send(.key(.end))
            let moved = try await recorder.wait(after: initial.sequence, description: "native cursor reaches last tiny tab") { _ in true }
            session.send(.key(.arrowDown))
            let expanded = try await recorder.wait(after: moved.sequence, description: "native tiny overflow opens") { _ in true }
            for row in expanded.raster.cells {
                #expect(row[width..<(width + 8)].allSatisfy { $0.character == " " },
                        "Neighboring cells in: \(String(row.map(\.character)))")
            }
            #expect(expanded.raster.lines[0].contains("Selected: 0"))
            session.send(.key(.return))
            _ = try await recorder.wait(after: expanded.sequence, description: "native overflow selection still commits") {
                $0.raster.lines[0].contains("Selected: 2")
            }
            session.stop()
            #expect(try await run.value == .inputEnded)
        } catch {
            session.stop()
            _ = await run.result
            throw error
        }
    }

    @Test("A bounded native overflow viewport reveals the last cursor even when focus paint is suppressed",
          arguments: [false, true])
    func longOverflow(suppressed: Bool) async throws {
        let recorder = HostedFrameRecorder()
        let surface = HostedRasterSurface(surfaceSize: CellSize(width: 12, height: 30), appearance: .fallback,
                                          onFrame: { recorder.receive($0) })
        let session = try HostedSceneSession(for: TabStyleTestApp(suppressed: suppressed, count: 20),
                                            sceneID: "tab-style", surface: surface)
        let run = Task { try await session.start() }
        do {
            let initial = try await recorder.wait(description: "overflow strip") {
                $0.raster.lines[0].contains("More") && $0.focusedIdentity != nil
            }
            session.send(.key(.end))
            session.send(.key(.arrowDown))
            let expanded = try await recorder.wait(after: initial.sequence, description: "last native overflow cursor is visible") {
                $0.raster.lines.contains { $0.contains("Tab 19") }
                    && $0.raster.lines[0].contains("More ▴")
            }
            #expect(!expanded.raster.lines.dropFirst(2).contains { $0.contains("Tab 0") })
            #expect(expanded.raster.cells.dropFirst(8).flatMap { $0 }.allSatisfy { $0.character == " " })
            session.send(.key(.return))
            _ = try await recorder.wait(after: expanded.sequence, description: "overflow activation retains selected content") {
                $0.raster.lines.contains { $0.contains("Body 19") }
                    && $0.raster.lines[0].contains("More ▾")
            }
            session.stop()
            #expect(try await run.value == .inputEnded)
        } catch {
            session.stop()
            _ = await run.result
            throw error
        }
    }
}

private struct TabStyleTestApp {
    let theme: ChioTheme
    let suppressed: Bool
    let count: Int
    nonisolated init() { theme = .default; suppressed = false; count = 3 }
    nonisolated init(theme: ChioTheme = .default, suppressed: Bool, count: Int = 3) {
        self.theme = theme
        self.suppressed = suppressed
        self.count = count
    }
}

extension TabStyleTestApp: App {
    var body: some Scene {
        WindowGroup(id: "tab-style") {
            TabStyleTestView(theme: theme, suppressed: suppressed, count: count)
        }.exitOnKeys([])
    }
}

@MainActor
private struct TabStyleTestView {
    let theme: ChioTheme
    let suppressed: Bool
    let count: Int
    @State private var selection = 0
}

extension TabStyleTestView: View {
    var body: some View {
        TabView(selection: $selection) {
            ForEach(Array(0..<count), id: \.self) { index in
                Tab("Tab \(index)", value: index) { Text("Body \(index)") }
            }
        }
        .frame(height: 8)
        .focusEffectDisabled(suppressed)
        .chioTheme(theme)
    }
}

private struct TinyTabsTestApp {
    let width: Int
    nonisolated init() { width = 2 }
    nonisolated init(width: Int) { self.width = width }
}

extension TinyTabsTestApp: App {
    var body: some Scene {
        WindowGroup(id: "tiny-tabs") { TinyTabsTestView(width: width) }.exitOnKeys([])
    }
}

@MainActor
private struct TinyTabsTestView {
    let width: Int
    @State private var selection = 0
}

extension TinyTabsTestView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            TabView(selection: $selection) {
                ForEach(0..<3, id: \.self) { index in
                    Tab("Option \(index) with a long title", value: index) { EmptyView() }
                }
            }
            .frame(width: width, height: 8)
            Text("Selected: \(selection)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chioTheme(.default)
    }
}
