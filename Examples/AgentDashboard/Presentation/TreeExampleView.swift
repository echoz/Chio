import Chio
import SwiftTUI

@MainActor
struct TreeExampleView {
    @Environment(\.terminalSize) private var terminalSize
    @Environment(\.requestTermination) private var requestTermination
    @State private var isLight: Bool
    @State private var expanded: Set<Branch> = [.sources, .library, .presentation]
    @FocusState private var sourcesFocused: Bool

    init(light: Bool = false) { _isLight = State(wrappedValue: light) }

    private var theme: ChioTheme { isLight ? .light : .default }

    private func expansion(_ branch: Branch) -> Binding<Bool> {
        let storage = $expanded
        return Binding(get: { storage.wrappedValue.contains(branch) }, set: { opens in
            var next = storage.wrappedValue
            if opens { next.insert(branch) } else { next.remove(branch) }
            storage.wrappedValue = next
        })
    }

    private func file(_ name: String) -> some View {
        HStack(spacing: 1) {
            Text("·").foregroundStyle(theme.colors.mutedText)
            Text(name).lineLimit(1)
        }
    }

    private var folders: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup("Sources", isExpanded: expansion(.sources)) {
                DisclosureGroup("Chio", isExpanded: expansion(.library)) {
                    file("ChioTheme.swift")
                    DisclosureGroup("Presentation", isExpanded: expansion(.presentation)) {
                        file("SearchableList.swift")
                        file("ChioButtonStyle.swift")
                    }
                }
            }
            .focused($sourcesFocused)
            .defaultFocus($sourcesFocused, true)
            DisclosureGroup("Tests", isExpanded: expansion(.tests)) {
                file("ThemeTests.swift")
                file("SearchTests.swift")
                file("DisclosureTests.swift")
            }
            DisclosureGroup("Examples", isExpanded: expansion(.examples)) {
                file("Dashboard.swift")
                file("ProjectTree.swift")
            }
            DisclosureGroup("Notes", isExpanded: expansion(.notes)) {
                Text("No files yet.").foregroundStyle(theme.colors.mutedText)
            }
            file("Package.swift")
            file("README.md")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hints: some View {
        KeyHints {
            KeyHint("tab/⇧tab", "focus")
            KeyHint("↵/space", "fold")
            KeyHint("^T", "theme")
            KeyHint("^Q", "quit")
        }
    }

    private enum Branch: String, CaseIterable, Hashable, Codable, Sendable {
        case sources, library, presentation, tests, examples, notes
    }
}

extension TreeExampleView: View {
    var body: some View {
        let short = terminalSize.height < 24
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Text("chio").bold().foregroundStyle(theme.colors.accent)
                Text("/ project tree").foregroundStyle(theme.colors.secondaryText)
            }
            if !short {
                Text("A workspace, one branch at a time.").foregroundStyle(theme.colors.secondaryText)
                Spacer().frame(height: 1)
            }
            Text("Example workspace").bold().foregroundStyle(theme.colors.heading)
            ScrollView { folders }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Text("Expanded folders: \(expanded.count) / \(Branch.allCases.count)")
                .foregroundStyle(theme.colors.mutedText)
            HStack(spacing: 1) {
                Button("Expand all") { expanded = Set(Branch.allCases) }
                Button("Collapse all") { expanded = [] }
            }
            if short { hints } else { StatusBar { hints } }
        }
        .padding(.horizontal, short ? 0 : 1)
        .padding(.vertical, short ? 0 : 1)
        .frame(maxWidth: 76, maxHeight: .infinity, alignment: .topLeading)
        .frame(width: terminalSize.width, height: terminalSize.height, alignment: .top)
        .onKeyPress { press in
            guard press.modifiers == .ctrl else { return .ignored }
            switch press.key {
            case .character("t"): isLight.toggle()
            case .character("q"): _ = requestTermination()
            default: return .ignored
            }
            return .handled
        }
        .chioTheme(theme)
    }
}
