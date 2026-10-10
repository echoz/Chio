import Chio
import SwiftTUI

@MainActor
struct ViewportExampleView {
    @Environment(\.terminalSize) private var terminalSize
    @Environment(\.requestTermination) private var requestTermination
    @State private var themeChoice: ExampleTheme
    @State private var position = ScrollCellOffset.zero
    @FocusState private var isLogFocused: Bool

    init(theme: ExampleTheme = .default) { _themeChoice = State(wrappedValue: theme) }

    private var theme: ChioTheme { themeChoice.theme }

    private var hints: some View {
        KeyHints {
            KeyHint("↑↓←→", "scroll")
            KeyHint("home/end", "jump")
            KeyHint("tab", "focus")
            KeyHint("F6", "log")
            KeyHint("^T", "theme")
            KeyHint("^Q", "quit")
        }
    }

    private func event(_ index: Int) -> some View {
        let agent = ["Build", "Review", "Test", "Docs"][(index - 1) % 4]
        let detail = ["Compiled the workspace", "Reviewed the changes", "Ran the test suite", "Published local documentation"][(index - 1) % 4]
        let number = Text("\(index < 10 ? "0" : "")\(index)").foregroundStyle(theme.colors.mutedText)
        let marker = Text("✓").foregroundStyle(theme.colors.success)
        let agentName = "\(agent) agent"
        let name = Text(verbatim: agentName).bold()
        let run = Text("run \(1000 + index)").foregroundStyle(theme.colors.secondaryText)
        // These fixed ASCII fixtures need columns, not independently laid-out controls.
        // Plain padding keeps emphasis on the agent name and preserves columns 7, 21 and 81.
        let agentPadding = String(repeating: " ", count: 14 - agentName.count)
        let detailPadding = String(repeating: " ", count: 60 - detail.count)
        return Text("\(number)  \(marker)  \(name)\(agentPadding)\(detail)\(detailPadding)\(run)")
            .frame(width: 96, alignment: .leading)
    }
}

extension ViewportExampleView: View {
    var body: some View {
        let isShort = terminalSize.height < 24
        let logFocus = $isLogFocused
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Text("chio").bold().foregroundStyle(theme.colors.accent)
                Text("/ activity viewport").foregroundStyle(theme.colors.secondaryText)
            }
            if !isShort {
                Text("A little room for a wide view.").foregroundStyle(theme.colors.secondaryText)
                Spacer().frame(height: 1)
            }
            Text("Workspace activity").bold().foregroundStyle(theme.colors.heading)
            Text("40 local events · scroll for details").foregroundStyle(theme.colors.mutedText)
            ScrollView([.horizontal, .vertical], position: $position) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(1...40, id: \.self) { event($0) }
                }
            }
            .focused($isLogFocused)
            .defaultFocus($isLogFocused, true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(spacing: 1) {
                Button("Back to start") { position = .zero }
                Spacer(minLength: 0)
                Text("Row \(position.y + 1) · Col \(position.x + 1)")
                    .foregroundStyle(theme.colors.secondaryText)
            }
            if isShort { hints } else { StatusBar { hints } }
        }
        .padding(.horizontal, isShort ? 0 : 1)
        .padding(.vertical, isShort ? 0 : 1)
        .frame(maxWidth: 86, maxHeight: .infinity, alignment: .topLeading)
        .frame(width: terminalSize.width, height: terminalSize.height, alignment: .top)
        .onKeyPress { press in
            if press == KeyPress(.functionKey(6)) {
                logFocus.wrappedValue = true
                return .handled
            }
            guard press.modifiers == .ctrl else { return .ignored }
            switch press.key {
            case .character("t"): themeChoice = themeChoice.next
            case .character("q"): _ = requestTermination()
            default: return .ignored
            }
            return .handled
        }
        .chioTheme(theme)
    }
}
