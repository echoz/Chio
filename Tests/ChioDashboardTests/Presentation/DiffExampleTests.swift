@testable import ChioDashboard
import Chio
import Foundation
import SwiftTUIRuntime
import Testing

@MainActor
@Suite(.serialized)
struct DiffExampleTests {
    @Test("The bounded diff retains its controls, one native viewport and compact hints",
          arguments: [CellSize(width: 36, height: 18), CellSize(width: 100, height: 30),
                      CellSize(width: 160, height: 40), CellSize(width: 91, height: 30),
                      CellSize(width: 92, height: 30)], ExampleTheme.allCases)
    func layout(size: CellSize, appearance: ExampleTheme) throws {
        let rendered = DefaultRenderer().render(
            DiffExampleView(theme: appearance).environment(\.terminalSize, size),
            proposal: .init(width: size.width, height: size.height), frameInstant: .zero
        )
        let text = rendered.rasterSurface.lines.joined(separator: "\n")
        #expect(rendered.rasterSurface.size == size)
        #expect(rendered.diagnostics.runtime.issues.isEmpty)
        for label in ["/ changes", "Sources/Greeting.swift", "hunk 1/3", "^L view", "^F file", "^T theme", "^Q quit"] {
            #expect(text.contains(label))
        }
        #expect(text.contains(size.width >= 92 ? "Split" : "Unified"))
        #expect(text.contains("@@ -1,7 +1,11 @@"))
        #expect(text.contains("struct Greeting"))
        let route = try #require(rendered.semanticSnapshot.scrollRoutes.first)
        #expect(rendered.semanticSnapshot.scrollRoutes.count == 1)
        #expect(route.contentBounds.size.height > route.viewportRect.size.height)
        #expect(route.contentBounds.size.width >= route.viewportRect.size.width)
        let nodes = rendered.semanticSnapshot.accessibilityNodes
        #expect(nodes.contains { $0.role == .picker && $0.label == "File" && $0.isEnabled })
        #expect(nodes.contains { $0.role == .button && $0.label == "Previous hunk" && !$0.isEnabled })
        #expect(nodes.contains { $0.role == .button && $0.label == "Next hunk" && $0.isEnabled })
        let theme = appearance.theme
        #expect(rendered.rasterSurface.cells.flatMap { $0 }.contains {
            $0.style?.foregroundColor == theme.colors.accent
        })
    }

    @Test("Unified gutters advance independently and retain blank numbers on an absent side",
          arguments: ExampleTheme.allCases)
    func unifiedGutters(appearance: ExampleTheme) throws {
        let file = try gutterFixture()
        let rendered = DefaultRenderer().render(
            DiffFileView(file: file, split: false, minimumWidth: 60, sourceWidth: 9, activeHunk: 0)
                .chioTheme(appearance.theme),
            proposal: .init(width: 80, height: 15)
        )
        let lines = rendered.rasterSurface.lines
        #expect(lines.contains { $0.contains("@@ -99,5 +99,3 @@") })
        let cells = rendered.rasterSurface.cells
        let context = try #require(lines.firstIndex { $0.contains("context") })
        #expect(cellText(cells[context], from: 0, count: 3) == " 99")
        #expect(cellText(cells[context], from: 4, count: 3) == " 99")
        for (text, number) in [("old-one", "100"), ("old-two", "101"), ("old-three", "102")] {
            let row = try #require(lines.firstIndex { $0.contains(text) })
            #expect(cellText(cells[row], from: 0, count: 3) == number)
            #expect(cellText(cells[row], from: 4, count: 3) == "   ")
            #expect(cells[row][8].character == "−")
        }
        let added = try #require(lines.firstIndex { $0.contains("new-one") })
        #expect(cellText(cells[added], from: 0, count: 3) == "   ")
        #expect(cellText(cells[added], from: 4, count: 3) == "100")
        #expect(cells[added][8].character == "+")
        let tail = try #require(lines.firstIndex { $0.contains("tail") })
        #expect(cellText(cells[tail], from: 0, count: 3) == "103")
        #expect(cellText(cells[tail], from: 4, count: 3) == "101")
        #expect(tail == context + 5)
    }

    @Test("Split replacements share rows and uneven removals leave the opposite cells empty",
          arguments: ExampleTheme.allCases)
    func splitGutters(appearance: ExampleTheme) throws {
        let rendered = DefaultRenderer().render(
            DiffFileView(file: try gutterFixture(), split: true, minimumWidth: 60,
                         sourceWidth: 9, activeHunk: 0).chioTheme(appearance.theme),
            proposal: .init(width: 80, height: 15)
        )
        let lines = rendered.rasterSurface.lines
        let cells = rendered.rasterSurface.cells
        let context = try #require(lines.firstIndex { $0.contains("context") })
        // A 60-cell minimum assigns 28 cells per pane and a three-cell separator.
        #expect(cellText(cells[context], from: 0, count: 3) == " 99")
        #expect(cells[context][29].character == "│")
        #expect(cellText(cells[context], from: 31, count: 3) == " 99")
        let paired = try #require(lines.firstIndex { $0.contains("old-one") })
        #expect(lines[paired].contains("new-one"))
        #expect(cellText(cells[paired], from: 0, count: 3) == "100")
        #expect(cellText(cells[paired], from: 31, count: 3) == "100")
        #expect(cells[paired][4].character == "−")
        #expect(cells[paired][35].character == "+")
        let theme = appearance.theme
        #expect(cells[paired][4].style?.foregroundColor == theme.colors.accent)
        #expect(cells[paired][35].style?.foregroundColor == theme.syntax.string)
        for (text, number) in [("old-two", "101"), ("old-three", "102")] {
            let row = try #require(lines.firstIndex { $0.contains(text) })
            #expect(cellText(cells[row], from: 0, count: 3) == number)
            #expect(cellText(cells[row], from: 31, count: 28) == String(repeating: " ", count: 28))
            #expect(cells[row][29].character == "│")
        }
        let tail = try #require(lines.firstIndex { $0.contains("tail") })
        #expect(tail == context + 4)
        #expect(cellText(cells[tail], from: 0, count: 3) == "103")
        #expect(cellText(cells[tail], from: 31, count: 3) == "101")
    }

    @Test("Literal Unicode, tabs, trailing spaces and blank source rows survive native composition",
          arguments: [false, true])
    func literalSource(split: Bool) throws {
        let unicode = "  cafe\u{301} 界 🐚  "
        let old = "\told  "
        let new = "\tnew   "
        let hunk = try DiffFile.Hunk(oldOffset: 0, newOffset: 0, blocks: [
            .context(unicode), .context(""), .change(removed: [old], added: [new]),
        ])
        let file = try DiffFile(id: "literal-source", change: .modified(path: "literal.swift"), content: .text([hunk]))
        // Widths come from the public native layout API, never grapheme counts.
        let sourceWidth = [unicode, old, new].map { layoutText(for: $0, width: nil).size.width }.max() ?? 0
        #expect(sourceWidth == 14)
        #expect(layoutText(for: old, width: nil).size.width == 6)
        #expect(layoutText(for: new, width: nil).size.width == 7)
        let rendered = DefaultRenderer().render(
            ScrollView([.horizontal, .vertical]) {
                DiffFileView(file: file, split: split, minimumWidth: 96, sourceWidth: sourceWidth, activeHunk: 0)
            }.frame(width: 96, height: 15).chioTheme(.default),
            proposal: .init(width: 96, height: 15)
        )
        for source in [unicode, old, new] {
            #expect(rendered.semanticSnapshot.accessibilityNodes.contains {
                $0.label.map { Array($0.utf8) == Array(source.utf8) } == true
            })
        }
        let route = try #require(rendered.semanticSnapshot.scrollRoutes.first)
        #expect(rendered.semanticSnapshot.scrollRoutes.count == 1)
        #expect(route.contentBounds.size.height == 6)
        #expect(route.contentBounds.size.width == (split ? 95 : 96))
        let text = rendered.rasterSurface.lines.joined(separator: "\n")
        #expect(text.contains("@@ -1,3 +1,3 @@"))
        #expect(text.contains("界") && text.contains("🐚"))
    }

    @Test("Unsupported and empty content has explicit summaries rather than invented source rows",
          arguments: [2, 3, 4, 5], [false, true])
    func summaries(index: Int, split: Bool) {
        let expected = [
            2: "Empty file added.",
            3: "Empty file deleted.",
            4: "Renamed from Docs/GettingStarted.md. No textual changes.",
            5: "Binary content · no source lines to display.",
        ][index]!
        let rendered = DefaultRenderer().render(
            DiffFileView(file: DiffFile.examples[index], split: split, minimumWidth: 100,
                         sourceWidth: 0, activeHunk: nil).chioTheme(.default),
            proposal: .init(width: 100, height: 8)
        )
        let text = rendered.rasterSurface.lines.joined(separator: "\n")
        #expect(text.contains(expected))
        #expect(!text.contains("@@") && !text.contains("BEFORE") && !text.contains("AFTER"))
        #expect(rendered.semanticSnapshot.accessibilityNodes.contains { $0.label == expected })
    }

    @Test("Logical hunk navigation survives mode, theme and responsive layout changes")
    func hunkWorkflow() async throws {
        try await withDiffExample { session, surface, recorder in
            let ready = try await recorder.wait(description: "split diff starts with native reader focus") {
                $0.diffReaderFocused && $0.diffContains("Split · hunk 1/3")
            }
            session.send(.key(.character("]")))
            let second = try await recorder.wait(after: ready.sequence, description: "next hunk reveals its authored old and new ranges") {
                $0.diffReaderFocused && $0.diffContains("hunk 2/3") && $0.diffContains("@@ -39,3 +43,4 @@")
                    && ($0.semantics.scrollRoutes.first?.contentOffset.y ?? 0) > 0
            }
            session.send([.key(.character("]")), .key(.character("]"))])
            let last = try await recorder.wait(after: second.sequence, description: "next stops at the last hunk") {
                $0.diffReaderFocused && $0.diffContains("hunk 3/3") && $0.diffContains("@@ -79,6 +84,4 @@")
                    && $0.diffButtonDisabled("Next hunk")
            }
            session.send(.key(.character("l"), modifiers: .ctrl))
            let unified = try await recorder.wait(after: last.sequence, description: "unified mode re-reveals the same logical hunk") {
                $0.diffReaderFocused && $0.diffContains("Unified · hunk 3/3") && $0.diffContains("@@ -79,6 +84,4 @@")
            }
            session.send(.key(.character("t"), modifiers: .ctrl))
            let themed = try await recorder.wait(after: unified.sequence, description: "light theme repaints source while retaining native focus and hunk") {
                guard let row = $0.raster.lines.firstIndex(where: { $0.contains("names.forEach(welcome)") }),
                      let range = $0.raster.lines[row].range(of: "names.forEach(welcome)") else { return false }
                // This fixture's prefix is ASCII, so string and cell columns coincide.
                let column = $0.raster.lines[row].distance(from: $0.raster.lines[row].startIndex, to: range.lowerBound)
                return $0.diffContains("Unified · hunk 3/3") && $0.diffContains("@@ -79,6 +84,4 @@")
                    && $0.focusedIdentity == unified.focusedIdentity
                    && $0.raster.cells[row][column].style?.foregroundColor == ChioTheme.light.syntax.string
            }
            surface.updateSurfaceSize(.init(width: 36, height: 18))
            session.requestSurfaceRefresh()
            let narrow = try await recorder.wait(after: themed.sequence, description: "compact resize retains the last hunk and reader focus") {
                $0.raster.size == CellSize(width: 36, height: 18) && $0.diffContains("Unified · hunk 3/3")
                    && $0.diffContains("@@ -79,6 +84,4 @@") && $0.diffReaderFocused
                    && $0.focusedIdentity == themed.focusedIdentity
            }
            surface.updateSurfaceSize(.init(width: 160, height: 40))
            session.requestSurfaceRefresh()
            let wide = try await recorder.wait(after: narrow.sequence, description: "widening retains the requested unified mode and selected hunk") {
                $0.raster.size == CellSize(width: 160, height: 40) && $0.diffContains("Unified · hunk 3/3")
                    && $0.diffContains("@@ -79,6 +84,4 @@") && $0.diffReaderFocused
            }
            session.send(.key(.character("l"), modifiers: .ctrl))
            let split = try await recorder.wait(after: wide.sequence, description: "split mode keeps the same last hunk") {
                $0.diffContains("Split · hunk 3/3") && $0.diffContains("@@ -79,6 +84,4 @@") && $0.diffReaderFocused
            }
            surface.updateSurfaceSize(.init(width: 36, height: 18))
            session.requestSurfaceRefresh()
            let fallback = try await recorder.wait(after: split.sequence, description: "narrow terminals temporarily use unified rows") {
                $0.raster.size == CellSize(width: 36, height: 18) && $0.diffContains("Unified · hunk 3/3") && $0.diffReaderFocused
            }
            surface.updateSurfaceSize(.init(width: 100, height: 30))
            session.requestSurfaceRefresh()
            let restored = try await recorder.wait(after: fallback.sequence, description: "widening restores the split preference and logical hunk") {
                $0.diffContains("Split · hunk 3/3") && $0.diffContains("@@ -79,6 +84,4 @@") && $0.diffReaderFocused
            }
            session.send(Array(repeating: .key(.character("[")), count: 3))
            let first = try await recorder.wait(after: restored.sequence, description: "previous stops at the first authored hunk") {
                $0.diffContains("Split · hunk 1/3") && $0.diffContains("@@ -1,7 +1,11 @@")
                    && $0.diffButtonDisabled("Previous hunk") && $0.diffReaderFocused
            }
            #expect(first.semantics.scrollRoutes.count == 1)
            #expect(first.focusedIdentity == ready.focusedIdentity)
            session.send([.key(.character("l"), modifiers: .ctrl), .key(.character("]"))])
            let batched = try await recorder.wait(after: first.sequence, description: "batched mode and hunk changes reveal the new logical target") {
                $0.diffContains("Unified · hunk 2/3") && $0.diffContains("@@ -39,3 +43,4 @@") && $0.diffReaderFocused
            }
            session.send([.key(.character("f"), modifiers: .ctrl), .key(.character("]"))])
            _ = try await recorder.wait(after: batched.sequence, description: "batched file and hunk changes use the newly selected file") {
                $0.diffContains("Fixtures/Unicode.swift") && $0.diffContains("Unified · hunk 1/1")
                    && $0.diffContains("@@ -9,6 +9,7 @@") && $0.diffReaderFocused
            }
        }
    }

    @Test("Native horizontal navigation reaches long source and file changes retain the reader")
    func longSourceAndFiles() async throws {
        try await withDiffExample(initialSize: .init(width: 36, height: 18), initialFile: 1, split: false) {
            session, _, recorder in
            let ready = try await recorder.wait(description: "Unicode fixture starts in the compact native reader") {
                $0.diffContains("Fixtures/Unicode.swift") && $0.diffContains("Unified · hunk 1/1") && $0.diffReaderFocused
            }
            session.send(.key(.end))
            let bottom = try await recorder.wait(after: ready.sequence, description: "End reaches the final source rows") {
                guard let route = $0.semantics.scrollRoutes.first else { return false }
                return $0.diffReaderFocused && route.contentOffset.y == route.contentBounds.size.height - route.viewportRect.size.height
                    && $0.diffContains("Trailing spaces")
            }
            session.send(Array(repeating: .key(.arrowRight), count: 200))
            let right = try await recorder.wait(after: bottom.sequence, description: "native right arrows expose the long source suffix and clamp") {
                guard let route = $0.semantics.scrollRoutes.first else { return false }
                return $0.diffReaderFocused && $0.diffContains("END_OF_SOURCE")
                    && route.contentOffset.x == route.contentBounds.size.width - route.viewportRect.size.width
                    && route.contentOffset.x > 0
            }
            #expect(right.semantics.scrollRoutes.count == 1)
            session.send(.key(.arrowLeft))
            let left = try await recorder.wait(after: right.sequence, description: "left reverses immediately from the horizontal edge") {
                $0.diffReaderFocused && $0.semantics.scrollRoutes.first?.contentOffset.x == right.semantics.scrollRoutes.first!.contentOffset.x - 1
            }
            session.send(.key(.character("f"), modifiers: .ctrl))
            var current = try await recorder.wait(after: left.sequence, description: "next file resets the native viewport to an empty added summary") {
                $0.diffContains("Fixtures/empty.txt") && $0.diffContains("Empty file added.")
                    && $0.diffContains("Unified · summary") && $0.diffReaderFocused
                    && $0.semantics.scrollRoutes.first?.contentOffset == .zero
            }
            for (path, summary) in [
                ("Fixtures/obsolete.txt", "Empty file deleted."),
                ("Docs/Guide.md", "Renamed from Docs/GettingStarted.md."),
                ("Assets/mark.png", "Binary content"),
            ] {
                session.send(.key(.character("f"), modifiers: .ctrl))
                current = try await recorder.wait(after: current.sequence, description: "next file shows its explicit summary: \(path)") {
                    $0.diffContains(path) && $0.diffContains(summary) && $0.diffContains("Unified · summary") && $0.diffReaderFocused
                }
                #expect(current.diffButtonDisabled("Previous hunk") && current.diffButtonDisabled("Next hunk"))
                #expect(current.semantics.scrollRoutes.count == 1)
            }
            session.send(.key(.character("f"), modifiers: .ctrl))
            _ = try await recorder.wait(after: current.sequence, description: "file cycling returns to the first hunk of the greeting") {
                $0.diffContains("Sources/Greeting.swift") && $0.diffContains("Unified · hunk 1/3")
                    && $0.diffContains("@@ -1,7 +1,11 @@") && $0.diffReaderFocused
            }
        }
    }
}

private func gutterFixture() throws -> DiffFile {
    try DiffFile(id: "gutters", change: .modified(path: "gutters.swift"), content: .text([
        try DiffFile.Hunk(oldOffset: 98, newOffset: 98, blocks: [
            .context("context"),
            .change(removed: ["old-one", "old-two", "old-three"], added: ["new-one"]),
            .context("tail"),
        ]),
    ]))
}

private func cellText(_ cells: [RasterCell], from start: Int, count: Int) -> String {
    String(cells[start..<(start + count)].map(\.character))
}

private struct DiffExampleTestApp {
    let initialFile: Int
    let split: Bool

    nonisolated init(initialFile: Int, split: Bool) {
        self.initialFile = initialFile
        self.split = split
    }
}

extension DiffExampleTestApp: App {
    nonisolated init() { self.init(initialFile: 0, split: true) }

    var body: some Scene {
        WindowGroup(id: "diff-example-tests") { DiffExampleView(initialFile: initialFile, split: split) }.exitOnKeys([])
    }
}

@MainActor
private func withDiffExample(
    initialSize: CellSize = .init(width: 100, height: 30), initialFile: Int = 0, split: Bool = true,
    perform: @MainActor (HostedSceneSession, HostedRasterSurface, HostedFrameRecorder) async throws -> Void
) async throws {
    let recorder = HostedFrameRecorder()
    let surface = HostedRasterSurface(surfaceSize: initialSize, appearance: .fallback,
                                      onFrame: { recorder.receive($0) })
    let app = DiffExampleTestApp(initialFile: initialFile, split: split)
    let session = try HostedSceneSession(
        for: app, sceneID: "diff-example-tests", surface: surface,
        runtimeIssueSink: RuntimeIssueSink { issue in
            Issue.record("Unexpected diff runtime issue: \(issue)")
        }
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
    func diffContains(_ value: String) -> Bool { raster.lines.contains { $0.contains(value) } }
    var diffReaderFocused: Bool {
        semantics.accessibilityNodes.contains {
            $0.identity == focusedIdentity && ($0.role == .scrollView || $0.role == .scrollViewWithIndicators)
        }
    }
    func diffButtonDisabled(_ label: String) -> Bool {
        semantics.accessibilityNodes.contains { $0.role == .button && $0.label == label && !$0.isEnabled }
    }
}
