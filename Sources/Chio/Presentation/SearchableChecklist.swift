import SwiftTUIViews

/// Searchable multiple choice, with persistent checkmarks and native row focus.
///
/// Items need stable, unique IDs. Arrows move focus; Space or Return toggles a
/// row. Filtering never changes membership. Hidden and removed IDs remain in the
/// binding, and disabled choices cannot be toggled in either direction. Apps own
/// validation, selection limits, submission, and explicit removal of stale IDs.
/// Rows are passive presentation; put buttons and editors outside the checklist.
@MainActor
public struct SearchableChecklist<Item: Identifiable, RowContent: View> where Item.ID: Sendable {
    private let items: [Item]
    private let selection: Binding<Set<Item.ID>>
    private let externalQuery: Binding<String>?
    private let prompt: String
    private let searchText: (Item) -> String
    private let isEnabled: (Item) -> Bool
    private let rowContent: @MainActor (Item) -> RowContent
    private let filter: SearchFilter
    private let resultKeyPress: (@MainActor @Sendable (KeyPress) -> KeyPressResult)?

    @State private var internalQuery = ""
    @State private var resultsRequested = false
    @FocusState private var searchFocused: Bool
    @Namespace private var resultsScope
    @Environment(\.resetFocus) private var resetFocus
    @Environment(\.chioTheme) private var theme

    public init<Items: RandomAccessCollection>(
        _ items: Items,
        selection: Binding<Set<Item.ID>>,
        query: Binding<String>? = nil,
        prompt: String = "Search…",
        searchText: @escaping (Item) -> String,
        isEnabled: @escaping (Item) -> Bool = { _ in true },
        @ViewBuilder rowContent: @escaping @MainActor (Item) -> RowContent
    ) where Items.Element == Item {
        self.items = Array(items)
        self.selection = selection
        externalQuery = query
        self.prompt = prompt
        self.searchText = searchText
        self.isEnabled = isEnabled
        self.rowContent = rowContent
        filter = .fuzzy
        resultKeyPress = nil
    }

    private init(
        copying source: Self,
        filter: SearchFilter? = nil,
        resultKeyPress: (@MainActor @Sendable (KeyPress) -> KeyPressResult)? = nil
    ) {
        items = source.items
        selection = source.selection
        externalQuery = source.externalQuery
        prompt = source.prompt
        searchText = source.searchText
        isEnabled = source.isEnabled
        rowContent = source.rowContent
        self.filter = filter ?? source.filter
        self.resultKeyPress = resultKeyPress ?? source.resultKeyPress
        _internalQuery = source._internalQuery
        _resultsRequested = source._resultsRequested
        _searchFocused = source._searchFocused
        _resultsScope = source._resultsScope
        _resetFocus = source._resetFocus
        _theme = source._theme
    }

    public func filtering(_ filter: SearchFilter) -> Self {
        Self(copying: self, filter: filter)
    }

    /// Handles application shortcuts only in results, after the checklist's
    /// search handoff. Ordinary characters remain text in the native editor.
    public func onResultKeyPress(
        perform action: @escaping @MainActor @Sendable (KeyPress) -> KeyPressResult
    ) -> Self {
        Self(copying: self, resultKeyPress: action)
    }

    private var query: Binding<String> { externalQuery ?? $internalQuery }

    private var visibleItems: [Item] {
        SearchMatcher.filtered(items, query: query.wrappedValue, filter: filter, searchText: searchText)
    }

    private var editableSelection: Binding<Set<Item.ID>> {
        Binding(get: { selection.wrappedValue }, set: { proposed in
            // Read the current query and bound value at dispatch time. A native
            // row from the preceding frame must not edit a newly hidden choice.
            let editableIDs = Set(visibleItems.filter(isEnabled).map(\.id))
            let accepted = ChecklistSelection.applying(
                proposed, to: selection.wrappedValue, editableIDs: editableIDs
            )
            if accepted != selection.wrappedValue { selection.wrappedValue = accepted }
        })
    }

    private func toggle(_ id: Item.ID) {
        editableSelection.wrappedValue = selection.wrappedValue.symmetricDifference([id])
    }

    private func requestResults(in scope: Namespace.ID, using reset: ResetFocusAction) {
        guard !visibleItems.isEmpty else { return }
        resultsRequested = true
        reset(in: scope)
    }

    private func carrySearchInput(_ press: KeyPress, requestResults: () -> Void) -> KeyPressResult {
        guard press.modifiers.subtracting(.shift).isEmpty else { return .ignored }
        // Focus changes commit with the next frame. Do not let later keys in
        // the same terminal read toggle rows from the preceding result set.
        if resultsRequested { return .handled }
        guard searchFocused else { return .ignored }
        let storage = query
        switch press.key {
        case .character(let character): storage.wrappedValue.append(character)
        case .space: storage.wrappedValue.append(" ")
        case .backspace:
            if !storage.wrappedValue.isEmpty { storage.wrappedValue.removeLast() }
        case .return: requestResults()
        case .escape:
            storage.wrappedValue = ""
            requestResults()
        case .tab: return .ignored
        default: return .ignored
        }
        return .handled
    }
}

extension SearchableChecklist: View {
    public var body: some View {
        let visible = visibleItems
        let selected = selection.wrappedValue
        let visibleIDs = Set(visible.map(\.id))
        let hiddenCount = selected.intersection(Set(items.map(\.id))).subtracting(visibleIDs).count
        let unavailableCount = selected.subtracting(Set(items.filter(isEnabled).map(\.id))).count
        // Namespace is resolved during body evaluation. Re-reading its wrapper
        // inside a deferred key handler can use a different authoring scope.
        let scope = resultsScope
        let reset = resetFocus
        let request: @MainActor () -> Void = { requestResults(in: scope, using: reset) }

        VStack(alignment: .leading, spacing: theme.spacing.sectionGap) {
            TextField(prompt, text: query)
                .focused($searchFocused)
                .onKeyPress(.return) { _ in
                    request()
                    return .handled
                }
                .onKeyPress(.escape) { _ in
                    query.wrappedValue = ""
                    request()
                    return .handled
                }
                .onKeyPress { press in
                    resultsRequested && press.modifiers.subtracting(.shift).isEmpty ? .handled : .ignored
                }

            if visible.isEmpty {
                Text(items.isEmpty ? "No items yet." : "No matches. Clear the search to see all items.")
                    .foregroundStyle(theme.colors.secondaryText)
            }

            List(visible, selection: editableSelection, onActivate: toggle) { item in
                let checked = selected.contains(item.id)
                let enabled = isEnabled(item)
                HStack(alignment: .top, spacing: theme.spacing.horizontalInset) {
                    Text(checked ? "[x]" : "[ ]")
                        .foregroundStyle(enabled ? theme.colors.accent : theme.colors.mutedText)
                    rowContent(item)
                    if !enabled {
                        Text("Unavailable").foregroundStyle(theme.colors.mutedText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(enabled ? theme.colors.foreground : theme.colors.mutedText)
                .background(checked ? theme.colors.selectedSurface : theme.colors.surface)
                .disabled(!enabled)
            }
            // Resetting this native scope reaches its first native row without
            // manufacturing a cursor or focusing the list's geometric center.
            .focusable(false)
            .focusScope(scope)
            .onKeyPress(.character("/")) { _ in
                searchFocused = true
                return .handled
            }
            .onKeyPress(.escape) { _ in
                query.wrappedValue = ""
                return .handled
            }
            .onKeyPress { press in
                let carried = carrySearchInput(press, requestResults: request)
                if carried == .handled { return .handled }
                return resultKeyPress?(press) ?? .ignored
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 0) {
                Text("\(visible.count) of \(items.count) items · \(selected.count) selected")
                if hiddenCount > 0 || unavailableCount > 0 {
                    Text("\(hiddenCount) hidden · \(unavailableCount) unavailable")
                }
            }
            .foregroundStyle(theme.colors.mutedText)
        }
        .onAppear { searchFocused = true }
        .onChange(of: searchFocused) {
            if !searchFocused { resultsRequested = false }
        }
    }
}
