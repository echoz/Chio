import Chio
import SwiftTUI

@MainActor
struct AgentReportView {
    let report: AgentReport
    @Binding var isLight: Bool
    let close: @MainActor @Sendable () -> Void
    @FocusState private var isReading: Bool
    @State private var lastLinkDestination = ""

    private var theme: ChioTheme { isLight ? .light : .default }
}

extension AgentReportView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 1) {
                Text("chio").bold().foregroundStyle(theme.colors.accent)
                Text("/ agent report").foregroundStyle(theme.colors.secondaryText)
                Spacer(minLength: 1)
                Text("snapshot").foregroundStyle(theme.colors.mutedText)
            }
            ScrollView {
                MarkdownView(report.document, openLink: OpenLinkAction { destination in
                    lastLinkDestination = destination.rawValue
                    return true
                })
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .focused($isReading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            StatusBar {
                Text(lastLinkDestination.isEmpty ? "Links stay in this demo." : "Link: \(lastLinkDestination)")
                    .foregroundStyle(theme.colors.secondaryText)
                KeyHints {
                    KeyHint("↑↓", "scroll")
                    KeyHint("home/end", "jump")
                    KeyHint("tab", "focus")
                    KeyHint("enter", "link")
                    KeyHint("esc", "back")
                    KeyHint("^T", "theme")
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
        .frame(maxWidth: 84, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .chioTheme(theme)
        .onAppear {
            lastLinkDestination = ""
            isReading = true
        }
        .onKeyPress(.escape) { _ in
            close()
            return .handled
        }
        .onKeyPress { press in
            guard press == KeyPress(.character("t"), modifiers: .ctrl) else { return .ignored }
            isLight.toggle()
            return .handled
        }
    }
}
