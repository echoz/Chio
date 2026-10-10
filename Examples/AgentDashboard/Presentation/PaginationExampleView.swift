import Chio
import Foundation
import SwiftTUI

@MainActor
struct PaginationExampleView {
    @Environment(\.terminalSize) private var terminalSize
    @Environment(\.requestTermination) private var requestTermination
    @State private var themeChoice: ExampleTheme
    @State private var query = ""
    @State private var pagination = Pagination(totalCount: 23, pageSize: 3)
    @FocusState private var isSearchFocused: Bool

    init(theme: ExampleTheme = .default) { _themeChoice = State(wrappedValue: theme) }

    private var theme: ChioTheme { themeChoice.theme }
    private static let entries = (1...23).map { index in
        Entry(id: index, title: ["Build", "Review", "Test", "Docs"][(index - 1) % 4],
              outcome: index % 5 == 0 ? .failed : .passed)
    }

    private static func matching(_ query: String) -> [Entry] {
        entries.filter { query.isEmpty || "\($0.title) \($0.outcome.rawValue)".localizedCaseInsensitiveContains(query) }
    }

    private var queryBinding: Binding<String> {
        let text = $query
        let pages = $pagination
        return Binding(get: { text.wrappedValue }, set: { value in
            text.wrappedValue = value
            // A changed filter starts a new result set. Commit its count and
            // initial page together before another input event can navigate.
            pages.wrappedValue = Pagination(totalCount: Self.matching(value).count,
                                            pageSize: pages.wrappedValue.pageSize)
        })
    }

    private var pageSizeBinding: Binding<Int> {
        let pages = $pagination
        return Binding(get: { pages.wrappedValue.pageSize }, set: {
            pages.wrappedValue = pages.wrappedValue.resizingPages(to: $0)
        })
    }

    private var hints: some View {
        KeyHints {
            KeyHint("tab", "focus")
            KeyHint("←→", "page")
            KeyHint("home/end", "jump")
            KeyHint("^R", "reset")
            KeyHint("^T", "theme")
            KeyHint("^Q", "quit")
        }
    }

    private struct Entry: Identifiable, Hashable, Codable, Sendable {
        let id: Int
        let title: String
        let outcome: Outcome
    }

    private enum Outcome: String, Hashable, Codable, Sendable {
        case passed = "Passed"
        case failed = "Failed"

        func color(in theme: ChioTheme) -> Color {
            switch self {
            case .passed: theme.colors.success
            case .failed: theme.colors.error
            }
        }
    }
}

extension PaginationExampleView: View {
    var body: some View {
        let isShort = terminalSize.height < 24
        let filtered = Self.matching(query)
        let visible = filtered[pagination.itemRange]
        let filter = queryBinding
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Text("chio").bold().foregroundStyle(theme.colors.accent)
                Text("/ run history").foregroundStyle(theme.colors.secondaryText)
            }
            if !isShort {
                Text("Find a run. Take the results one page at a time.")
                    .foregroundStyle(theme.colors.secondaryText)
                Spacer().frame(height: 1)
            }
            TextField("Filter history…", text: filter)
                .focused($isSearchFocused)
                .defaultFocus($isSearchFocused, true)
            HStack(spacing: 1) {
                Picker("Rows per page", selection: pageSizeBinding) {
                    Text("3").tag(3)
                    Text("5").tag(5)
                }
                Spacer(minLength: 0)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if visible.isEmpty {
                        Text("No matching runs.").bold()
                        Text("Change the filter or press Ctrl-R.").foregroundStyle(theme.colors.mutedText)
                    }
                    ForEach(visible) { entry in
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 1) {
                                Text("\(entry.title) \(entry.id < 10 ? "0" : "")\(entry.id)")
                                    .bold().lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                Text(entry.outcome.rawValue)
                                    .foregroundStyle(entry.outcome.color(in: theme))
                            }
                            Text("Local simulation · run \(entry.id)").foregroundStyle(theme.colors.mutedText)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, isShort ? 0 : 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            PageControl(pagination: $pagination)
            if isShort { hints } else { StatusBar { hints } }
        }
        .padding(.horizontal, isShort ? 0 : 1)
        .padding(.vertical, isShort ? 0 : 1)
        .frame(maxWidth: 76, maxHeight: .infinity, alignment: .topLeading)
        .frame(width: terminalSize.width, height: terminalSize.height, alignment: .top)
        .onKeyPress { press in
            guard press.modifiers == .ctrl else { return .ignored }
            switch press.key {
            case .character("r"): filter.wrappedValue = ""
            case .character("t"): themeChoice = themeChoice.next
            case .character("q"): _ = requestTermination()
            default: return .ignored
            }
            return .handled
        }
        .chioTheme(theme)
    }
}
