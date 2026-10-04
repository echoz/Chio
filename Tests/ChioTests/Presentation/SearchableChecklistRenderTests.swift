import Chio
import SwiftTUIRuntime
import Testing

@MainActor
struct SearchableChecklistRenderTests {
    @Test("Checkmarks, disabled choices and current counts remain readable in both themes and sizes",
          arguments: [ChioTheme.default, .light], [100, 36])
    func checklistAppearance(theme: ChioTheme, width: Int) throws {
        let rendered = DefaultRenderer().render(
            SearchableChecklist(ChecklistRenderItem.fixtures, selection: .constant(Set(["a", "b"])),
                                searchText: \.name, isEnabled: { $0.id != "b" }) { Text($0.name) }
                .chioTheme(theme),
            proposal: .init(width: width, height: width == 100 ? 30 : 18)
        )
        let surface = rendered.rasterSurface
        #expect(surface.size.width <= width)
        let alpha = try #require(surface.lines.first { $0.contains("Alpha") })
        let beta = try #require(surface.lines.first { $0.contains("Beta") })
        let quill = try #require(surface.lines.first { $0.contains("Quill") })
        #expect(alpha.contains("[x]"))
        #expect(beta.contains("[x]") && beta.contains("Unavailable"))
        #expect(quill.contains("[ ]"))
        #expect(surface.lines.contains { $0.contains("3 of 3 items · 2 selected") })
        #expect(surface.lines.contains { $0.contains("0 hidden · 1 unavailable") })
        let alphaRow = try #require(surface.lines.firstIndex { $0.contains("Alpha") })
        let betaRow = try #require(surface.lines.firstIndex { $0.contains("Beta") })
        #expect(surface.cells[alphaRow].contains {
            $0.character == "x" && $0.style?.foregroundColor == theme.colors.accent
        })
        #expect(surface.cells[betaRow].contains {
            $0.character == "B" && $0.style?.foregroundColor == theme.colors.mutedText
        })
        #expect(rendered.semanticSnapshot.accessibilityNodes.contains { $0.role == .textField })
        #expect(rendered.semanticSnapshot.accessibilityNodes.contains { $0.role == .list })
    }

    @Test("Empty source and unmatched search have distinct messages while retaining checked IDs",
          arguments: [false, true])
    func emptyStates(emptySource: Bool) {
        let surface = DefaultRenderer().render(
            SearchableChecklist(emptySource ? [] : ChecklistRenderItem.fixtures,
                                selection: .constant(Set(["a"])), query: .constant("zzz"),
                                searchText: \.name) { Text($0.name) }.chioTheme(.default),
            proposal: .init(width: 36, height: 18)
        ).rasterSurface
        let text = surface.lines.joined(separator: " ")
        #expect(text.contains(emptySource ? "No items yet." : "No matches."))
        #expect(text.contains(emptySource ? "0 of 0 items · 1 selected" : "0 of 3 items · 1 selected"))
        #expect(text.contains(emptySource ? "0 hidden · 1 unavailable" : "1 hidden · 0 unavailable"))
    }

    @Test("Replacing the filter preserves the original fuzzy configuration")
    func filterReplacement() {
        let original = SearchableChecklist(ChecklistRenderItem.fixtures, selection: .constant(Set<String>()),
                                           query: .constant("aa"), searchText: \.name) { Text($0.name) }
        let substring = original.filtering(.substring)
        let fuzzyText = DefaultRenderer().render(original.chioTheme(.default),
                                                proposal: .init(width: 36, height: 18)).rasterSurface.lines
        let substringText = DefaultRenderer().render(substring.chioTheme(.default),
                                                    proposal: .init(width: 36, height: 18)).rasterSurface.lines
        #expect(fuzzyText.contains { $0.contains("Alpha") })
        #expect(fuzzyText.contains { $0.contains("1 of 3 items · 0 selected") })
        #expect(substringText.contains { $0.contains("No matches.") })
        #expect(substringText.contains { $0.contains("0 of 3 items · 0 selected") })
    }
}

private struct ChecklistRenderItem {
    let id: String
    let name: String

    static let fixtures = [Self(id: "a", name: "Alpha"), Self(id: "b", name: "Beta"), Self(id: "q", name: "Quill")]
}

extension ChecklistRenderItem: Identifiable {}
