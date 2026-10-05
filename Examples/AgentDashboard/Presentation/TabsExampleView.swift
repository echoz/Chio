import Chio
import SwiftTUI

@MainActor
struct TabsExampleView {
    @Environment(\.terminalSize) private var terminalSize
    @Environment(\.requestTermination) private var requestTermination
    @State private var isLight: Bool
    @State private var section = Section.overview
    @FocusState private var stripFocused: Bool

    init(light: Bool = false) {
        _isLight = State(wrappedValue: light)
    }

    private enum Section: Hashable, Codable, Sendable {
        case overview, agents, notes, activity, settings
    }

    private var theme: ChioTheme { isLight ? .light : .default }
    private var hints: [ShortcutHint] {
        let navigation = stripFocused
            ? [ShortcutHint("←→", "choose"), ShortcutHint("↵", "open"), ShortcutHint("↓", "more")]
            : [ShortcutHint("F6", "tabs")]
        return navigation + [ShortcutHint("tab", "focus"), ShortcutHint("^T", "theme"), ShortcutHint("^Q", "quit")]
    }
}

extension TabsExampleView: View {
    var body: some View {
        let short = terminalSize.height < 24
        let stripFocus = $stripFocused
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Text("chio").bold().foregroundStyle(theme.colors.accent)
                Text("/ workspace tabs").foregroundStyle(theme.colors.secondaryText)
            }
            if !short {
                Text("Choose a section. Your drafts stay where you left them.")
                    .foregroundStyle(theme.colors.secondaryText)
                Spacer().frame(height: 1)
            }
            TabView(selection: $section) {
                Tab("Overview", value: Section.overview) { OverviewTab() }
                Tab("Agents", badge: "4", value: Section.agents) { AgentsTab() }
                Tab("Notes", value: Section.notes) { NotesTab() }
                Tab("Activity", value: Section.activity) { ActivityTab() }
                Tab("Settings", value: Section.settings) { SettingsTab() }
            }
            .focused($stripFocused)
            .defaultFocus($stripFocused, true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if short { KeyHints(hints) } else { StatusBar { KeyHints(hints) } }
        }
        .padding(.horizontal, short ? 0 : 1)
        .padding(.vertical, short ? 0 : 1)
        .frame(maxWidth: 76, maxHeight: .infinity, alignment: .topLeading)
        .frame(width: terminalSize.width, height: terminalSize.height, alignment: .top)
        .onKeyPress { press in
            if press == KeyPress(.functionKey(6)) {
                stripFocus.wrappedValue = true
                return .handled
            }
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
        .chioTheme(theme)
    }
}

// Each page owns value state so native TabView dormancy is exercised directly.
@MainActor
private struct OverviewTab {
    @Environment(\.chioTheme) private var theme
    @State private var runs = 0
}

extension OverviewTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Workspace overview").bold().foregroundStyle(theme.colors.heading)
            Text("A small workspace with room to move.")
                .foregroundStyle(theme.colors.secondaryText)
            Text("Demo runs: \(runs)").bold()
            Button("Run demo") { runs += 1 }
            Text("Local sample data. Nothing is sent or saved.")
                .foregroundStyle(theme.colors.mutedText)
            Spacer(minLength: 0)
        }
        .padding(.top, 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

@MainActor
private struct AgentsTab {
    @Environment(\.chioTheme) private var theme
    @State private var query = ""
    @State private var selection: Agent.ID? = Agent.examples.first?.id
}

extension AgentsTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Agent directory").bold().foregroundStyle(theme.colors.heading)
            SearchableList(Agent.examples, selection: $selection, query: $query, searchText: \.name) { agent in
                Text(agent.name)
            }
        }
        .padding(.top, 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

@MainActor
private struct NotesTab {
    @Environment(\.chioTheme) private var theme
    @Environment(\.terminalSize) private var terminalSize
    @State private var notes = ""
}

extension NotesTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Scratch notes").bold().foregroundStyle(theme.colors.heading)
            TextEditor(text: $notes).frame(height: terminalSize.height < 24 ? 4 : 8)
            Text("Characters: \(notes.count)").foregroundStyle(theme.colors.secondaryText)
            Text("Switch tabs and return to keep editing.").foregroundStyle(theme.colors.mutedText)
            Spacer(minLength: 0)
        }
        .padding(.top, 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

@MainActor
private struct ActivityTab {
    @Environment(\.chioTheme) private var theme
}

extension ActivityTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Activity log").bold().foregroundStyle(theme.colors.heading)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(1...40, id: \.self) { index in
                        Text("Event \(index < 10 ? "0" : "")\(index) · Workspace activity")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.top, 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

@MainActor
private struct SettingsTab {
    @Environment(\.chioTheme) private var theme
    @State private var quiet = false
}

extension SettingsTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Workspace settings").bold().foregroundStyle(theme.colors.heading)
            Toggle("Quiet mode", isOn: $quiet)
            Text("Quiet mode: \(quiet ? "on" : "off")").foregroundStyle(theme.colors.secondaryText)
            Text("This setting lasts for the current session.").foregroundStyle(theme.colors.mutedText)
            Spacer(minLength: 0)
        }
        .padding(.top, 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
