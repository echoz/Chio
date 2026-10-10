import SwiftTUIViews

/// A searchable native command palette with Chio's colors and compact rows.
public struct ChioPaletteStyle {
    public let theme: ChioTheme
    /// The query to use when a palette opens. Native editing owns subsequent changes.
    public let initialQuery: String

    public init(theme: ChioTheme = .default, initialQuery: String = "") {
        self.theme = theme
        self.initialQuery = initialQuery
    }
}

extension ChioPaletteStyle: PaletteStyle {
    @MainActor
    public func makeBody(configuration: PaletteStyleConfiguration) -> some View {
        ChioPaletteBody(configuration: configuration, theme: theme, initialQuery: initialQuery)
    }
}

extension ChioPaletteStyle: Equatable {}

@MainActor
private struct ChioPaletteBody {
    let configuration: PaletteStyleConfiguration
    let theme: ChioTheme
    let initialQuery: String

    @State private var query = ""
    @State private var selection: AnyID?
    @State private var visibleStart = 0
    @FocusState private var isSearchFocused: Bool
    @Namespace private var searchFocusNamespace

    init(configuration: PaletteStyleConfiguration, theme: ChioTheme, initialQuery: String) {
        self.configuration = configuration
        self.theme = theme
        self.initialQuery = initialQuery
        _query = State(wrappedValue: initialQuery)
    }

    private var matches: [PaletteStyleConfiguration.Command] {
        SearchMatcher.filtered(configuration.commands, query: query, filter: .fuzzy, searchText: \.name)
    }

    private var visibleIDs: [AnyID] { matches.map(\.id) }
    private var showsDescriptions: Bool { configuration.terminalSize.height >= 26 }
    private var rowHeight: Int { showsDescriptions ? 2 : 1 }
    private var maximumVisibleRows: Int {
        let height = min(16, max(8, configuration.terminalSize.height - 4))
        return max(1, (height - 7) / rowHeight)
    }

    private func windowStart(count: Int, selectedIndex: Int, preferredStart: Int) -> Int {
        let start = min(max(0, preferredStart), max(0, count - maximumVisibleRows))
        if selectedIndex < start { return selectedIndex }
        if selectedIndex >= start + maximumVisibleRows {
            return selectedIndex - maximumVisibleRows + 1
        }
        return start
    }

    private func moveSelection(by delta: Int, query: String,
                               selection: Binding<AnyID?>, visibleStart: Binding<Int>) {
        let rows = SearchMatcher.filtered(configuration.commands, query: query, filter: .fuzzy, searchText: \.name)
        let id = SearchSelection.reconciled(selection.wrappedValue, visibleIDs: rows.map(\.id))
        guard let current = rows.firstIndex(where: { $0.id == id }) else {
            selection.wrappedValue = nil
            visibleStart.wrappedValue = 0
            return
        }
        let next = min(max(0, current + delta), rows.count - 1)
        selection.wrappedValue = rows[next].id
        visibleStart.wrappedValue = windowStart(count: rows.count, selectedIndex: next,
                                               preferredStart: visibleStart.wrappedValue)
    }

    private func activateSelection(query: String, selection: Binding<AnyID?>) {
        // Reconcile from the current query, including input received before the next frame.
        let rows = SearchMatcher.filtered(configuration.commands, query: query, filter: .fuzzy, searchText: \.name)
        let id = SearchSelection.reconciled(selection.wrappedValue, visibleIDs: rows.map(\.id))
        selection.wrappedValue = id
        guard let command = rows.first(where: { $0.id == id }), command.isEnabled else { return }
        command.perform()
    }

    private func handleKey(_ press: KeyPress, query: Binding<String>,
                           selection: Binding<AnyID?>, visibleStart: Binding<Int>) -> KeyPressResult {
        if press == KeyPress(.tab, modifiers: .shift) {
            moveSelection(by: -1, query: query.wrappedValue, selection: selection, visibleStart: visibleStart)
            return .handled
        }
        guard press.modifiers.isEmpty else { return .ignored }
        switch press.key {
        case .arrowDown, .tab:
            moveSelection(by: 1, query: query.wrappedValue, selection: selection, visibleStart: visibleStart)
        case .arrowUp:
            moveSelection(by: -1, query: query.wrappedValue, selection: selection, visibleStart: visibleStart)
        case .return:
            activateSelection(query: query.wrappedValue, selection: selection)
        case .escape:
            configuration.dismiss()
        default:
            return .ignored
        }
        return .handled
    }

    private func row(_ command: PaletteStyleConfiguration.Command, isSelected: Bool) -> some View {
        command.route {
            Button { command.perform() } label: {
                HStack(alignment: .top, spacing: 1) {
                    Text(isSelected ? theme.treatments.selectionMarker : " ")
                        .foregroundStyle(command.isEnabled ? theme.colors.accent : theme.colors.mutedText)
                        .fixedSize()
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: command.name)
                            .foregroundStyle(command.isEnabled ? theme.colors.foreground : theme.colors.mutedText)
                        if showsDescriptions {
                            Text(verbatim: command.description ?? "")
                                .foregroundStyle(theme.colors.mutedText)
                        }
                    }
                    .lineLimit(1)
                    .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: rowHeight, alignment: .topLeading)
                .background(isSelected ? theme.colors.selectedSurface : theme.colors.surface)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(command.name)
            .focusable(false)
            .disabled(!command.isEnabled)
        }
    }
}

extension ChioPaletteBody: View {
    var body: some View {
        // Capture the same resolved bindings the editor uses. A palette may be
        // reopened after a cover; handlers must not recover a retired state owner.
        let queryBinding = $query
        let selectionBinding = $selection
        let startBinding = $visibleStart
        let rows = matches
        let selectedID = SearchSelection.reconciled(selection, visibleIDs: rows.map(\.id))
        let selectedIndex = rows.firstIndex { $0.id == selectedID } ?? 0
        let start = windowStart(count: rows.count, selectedIndex: selectedIndex, preferredStart: visibleStart)
        let visible = Array(rows.dropFirst(start).prefix(maximumVisibleRows))

        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: configuration.title).bold().foregroundStyle(theme.colors.heading)
            TextField("Filter commands…", text: $query)
                .textFieldStyle(ChioTextFieldStyle(theme: theme))
                .focused($isSearchFocused)
                .prefersDefaultFocus(in: searchFocusNamespace)
                .onKeyPress { press in
                    handleKey(press, query: queryBinding, selection: selectionBinding, visibleStart: startBinding)
                }
            VStack(alignment: .leading, spacing: 0) {
                if rows.isEmpty {
                    Text(configuration.commands.isEmpty ? "No commands available." : "No matches.")
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)
                } else {
                    ForEach(visible) { command in
                        row(command, isSelected: command.id == selectedID)
                    }
                }
            }
            Text("↑↓ select · ↵ run · esc close")
                .foregroundStyle(theme.colors.mutedText)
                .lineLimit(1)
        }
        .padding(.horizontal, 1)
        .foregroundStyle(theme.colors.foreground)
        .background(theme.colors.surface)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .focusScope(searchFocusNamespace)
        .onAppear {
            queryBinding.wrappedValue = initialQuery
            selectionBinding.wrappedValue = nil
            startBinding.wrappedValue = 0
            isSearchFocused = true
        }
        .onChange(of: visibleIDs, initial: true) { _, ids in
            selectionBinding.wrappedValue = SearchSelection.reconciled(selectionBinding.wrappedValue, visibleIDs: ids)
            startBinding.wrappedValue = 0
        }
    }
}
