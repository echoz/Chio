import Chio
import SwiftTUI

/// Shortcut descriptions are shared by both presentations; native controls
/// and key handlers remain the authority for what a key actually does.
@MainActor
struct HelpExampleView {
    @Environment(\.terminalSize) private var terminalSize
    @Environment(\.requestTermination) private var requestTermination
    @State private var isLight: Bool
    @State private var selection: Agent.ID? = Agent.examples.first?.id
    @State private var query = ""
    @State private var isSearching = false
    @State private var help: Context?
    @State private var runs = 0
    @FocusState private var actionFocus: Action?

    init(light: Bool = false) {
        _isLight = State(wrappedValue: light)
    }

    private enum Context { case browse, editing, actions, all }
    private enum Action: Hashable { case run, help }

    private static let navigate = ShortcutHint("↑↓", "move", detail: "Move through the visible agents.")
    private static let filter = ShortcutHint("/", "search", detail: "Type a name to filter the list.")
    private static let activate = ShortcutHint("↵", "activate", detail: "Run the selected agent, or activate the focused button.")
    private static let run = ShortcutHint("^R", "run", detail: "Run the selected agent. This example only updates a local count.")
    private static let browseHelp = ShortcutHint("?", "help", detail: "Show shortcuts while browsing or using an action button.")
    private static let editingHelp = ShortcutHint("F1", "help", detail: "Show the full shortcut reference without changing your search text.")
    private static let type = ShortcutHint("type", "filter", detail: "Characters, including ?, edit the search instead of opening help.")
    private static let finishSearch = ShortcutHint("↵", "results", detail: "Keep the filter and return to the result list.")
    private static let clear = ShortcutHint("esc", "clear", detail: "Clear the filter; leave search when it has focus.")
    private static let tab = ShortcutHint("tab", "next", detail: "Move between search, results, and action buttons. Shift-Tab moves back.")
    private static let theme = ShortcutHint("^T", "theme", detail: "Switch between Chio's dark and light themes without losing your place.")
    private static let quit = ShortcutHint("^Q", "quit", detail: "Exit this local example.")
    private static let scroll = ShortcutHint("↑↓ / pgup/pgdn", "scroll", detail: "Scroll the help viewport. Tab moves between the viewport and Close.")
    private static let close = ShortcutHint("esc", "close", detail: "Close help and return to the control you were using.")

    private var theme: ChioTheme { isLight ? .light : .default }
    private var selectedAgent: Agent? { Agent.examples.first { $0.id == selection } }
    private var context: Context {
        if actionFocus != nil { return .actions }
        return isSearching ? .editing : .browse
    }

    private var compactHints: [ShortcutHint] {
        switch context {
        case .browse: [Self.navigate, Self.filter, Self.browseHelp, Self.theme, Self.quit]
        case .editing: [Self.finishSearch, Self.clear, Self.editingHelp, Self.theme, Self.quit]
        case .actions: [Self.tab, Self.activate, Self.browseHelp, Self.theme, Self.quit]
        case .all: [Self.editingHelp, Self.theme, Self.quit]
        }
    }

    private var helpGroups: [ShortcutGroup] {
        let browse = ShortcutGroup("Browse", shortcuts: [Self.navigate, Self.filter, Self.activate, Self.clear, Self.tab])
        let editing = ShortcutGroup("Editing", shortcuts: [Self.type, Self.finishSearch, Self.clear, Self.editingHelp, Self.tab])
        let actions = ShortcutGroup("Actions", shortcuts: [Self.tab, Self.activate, Self.browseHelp])
        let contextual: [ShortcutGroup]
        switch help ?? context {
        case .browse: contextual = [browse]
        case .editing: contextual = [editing]
        case .actions: contextual = [actions]
        case .all: contextual = [browse, editing, actions]
        }
        let application = (selectedAgent == nil ? [] : [Self.run]) + [Self.theme, Self.quit]
        return contextual + [.init("Application", shortcuts: application),
                             .init("Help", shortcuts: [Self.scroll, Self.close])]
    }

    private var helpIsPresented: Binding<Bool> {
        let storage = $help
        return Binding(get: { storage.wrappedValue != nil }, set: {
            if !$0 { storage.wrappedValue = nil }
        })
    }

    private func runSelected() {
        guard selectedAgent != nil, help == nil else { return }
        runs += 1
    }

    private func openHelp(_ context: Context, for press: KeyPress) -> KeyPressResult {
        guard press.key == .character("?"), press.modifiers.subtracting(.shift).isEmpty else { return .ignored }
        help = context
        return .handled
    }

    private func backgroundKey(_ press: KeyPress) -> KeyPressResult {
        // An input batch can reach the background before help has acquired
        // native focus. Protect its query/actions and honor an immediate Escape.
        if help != nil {
            if press == KeyPress(.escape) { help = nil }
            if press == KeyPress(.character("t"), modifiers: .ctrl) { isLight.toggle() }
            if press == KeyPress(.character("q"), modifiers: .ctrl) { _ = requestTermination() }
            return .handled
        }
        if press == KeyPress(.functionKey(1)) {
            help = .all
            return .handled
        }
        guard press.modifiers == .ctrl else { return .ignored }
        switch press.key {
        case .character("r"): runSelected()
        case .character("t"): isLight.toggle()
        case .character("q"): _ = requestTermination()
        default: return .ignored
        }
        return .handled
    }
}

extension HelpExampleView: View {
    var body: some View {
        let short = terminalSize.height < 24
        let helpStorage = $help
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Text("chio").bold().foregroundStyle(theme.colors.accent)
                Text("/ keyboard help").foregroundStyle(theme.colors.secondaryText)
            }
            if !short {
                Text("A few hints now. The full picture when you need it.")
                    .foregroundStyle(theme.colors.secondaryText)
                Spacer().frame(height: 1)
            }
            SearchableList(Agent.examples, selection: $selection, query: $query, searchText: \.name) { agent in
                Text(agent.name)
            }
            .onActivate { _ in runSelected() }
            .onSearchFocusChange { isSearching = $0 }
            .onResultKeyPress { openHelp(.browse, for: $0) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("Runs: \(runs)").foregroundStyle(theme.colors.secondaryText)
            HStack(spacing: 1) {
                Button("Run", action: runSelected)
                    .disabled(selectedAgent == nil)
                    .focused($actionFocus, equals: .run)
                Button("Help") { helpStorage.wrappedValue = .actions }
                    .focused($actionFocus, equals: .help)
            }
            .onKeyPress { openHelp(.actions, for: $0) }
            if short { KeyHints(compactHints) } else { StatusBar { KeyHints(compactHints) } }
        }
        .padding(.horizontal, short ? 0 : 1)
        .padding(.vertical, short ? 0 : 1)
        .frame(maxWidth: 76, maxHeight: .infinity, alignment: .topLeading)
        .frame(width: terminalSize.width, height: terminalSize.height, alignment: .top)
        .onKeyPress(perform: backgroundKey)
        .fullScreenCover(isPresented: helpIsPresented) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Keyboard shortcuts").bold().foregroundStyle(theme.colors.heading)
                    Spacer(minLength: 1)
                    Button("Close") { helpStorage.wrappedValue = nil }
                }
                if help == .all {
                    Text("All shortcuts").foregroundStyle(theme.colors.secondaryText)
                }
                ScrollView(.vertical) {
                    KeyboardHelp(helpGroups)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.vertical, 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                KeyHints([Self.close, Self.theme, Self.quit])
            }
                .padding(.horizontal, short ? 0 : 1)
                .frame(maxWidth: 76, maxHeight: .infinity, alignment: .topLeading)
                .frame(width: terminalSize.width, height: terminalSize.height, alignment: .top)
                .chioTheme(theme)
                .onKeyPress { press in
                    if press == KeyPress(.character("t"), modifiers: .ctrl) {
                        isLight.toggle()
                        return .handled
                    }
                    if press == KeyPress(.character("q"), modifiers: .ctrl) {
                        _ = requestTermination()
                        return .handled
                    }
                    return .ignored
                }
        }
        .chioTheme(theme)
    }
}
