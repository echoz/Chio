import SwiftTUIViews

/// An always-visible search field and a native selectable, scrollable list.
///
/// Items must have stable, unique IDs. Filtering preserves a visible selection,
/// otherwise selects the first result, and never calls the activation action.
/// Rows are passive presentation; put buttons and editors outside the list.
/// Tab retains native row focus navigation, which is distinct from selection.
/// Enter activates the selected item, even when Tab has focused another row.
@MainActor
public struct SearchableList<Item: Identifiable, RowContent: View> where Item.ID: Sendable {
    private enum Focus: Hashable {
        case search
        case results
    }

    private let items: [Item]
    private let selection: Binding<Item.ID?>
    private let externalQuery: Binding<String>?
    private let searchText: (Item) -> String
    private let rowContent: @MainActor (Item) -> RowContent
    private let prompt: String
    private var filter: SearchFilter = .fuzzy
    private var activation: (@MainActor (Item) -> Void)?
    private var searchFocusChange: (@MainActor (Bool) -> Void)?
    private var resultKeyPress: (@MainActor @Sendable (KeyPress) -> KeyPressResult)?

    @State private var internalQuery = ""
    @FocusState private var focus: Focus?
    @Environment(\.chioTheme) private var theme

    public init<Items: RandomAccessCollection>(
        _ items: Items,
        selection: Binding<Item.ID?>,
        query: Binding<String>? = nil,
        prompt: String = "Search…",
        searchText: @escaping (Item) -> String,
        @ViewBuilder rowContent: @escaping @MainActor (Item) -> RowContent
    ) where Items.Element == Item {
        self.items = Array(items)
        self.selection = selection
        externalQuery = query
        self.prompt = prompt
        self.searchText = searchText
        self.rowContent = rowContent
    }

    /// Selects fuzzy ranking or ordered substring matching.
    public func filtering(_ filter: SearchFilter) -> Self {
        var copy = self
        copy.filter = filter
        return copy
    }

    /// Called when a result is explicitly activated, never merely filtered.
    public func onActivate(_ action: @escaping @MainActor (Item) -> Void) -> Self {
        var copy = self
        copy.activation = action
        return copy
    }

    /// Reports search focus for presentation such as contextual keyboard hints.
    /// Use `onResultKeyPress` to scope input; this render-driven callback can lag.
    public func onSearchFocusChange(_ action: @escaping @MainActor (Bool) -> Void) -> Self {
        var copy = self
        copy.searchFocusChange = action
        return copy
    }

    /// Handles application shortcuts only while the native results area has
    /// focus. Use this instead of guarding ancestor handlers with focus callbacks:
    /// those callbacks update after rendering and can lag rapidly typed input.
    public func onResultKeyPress(
        perform action: @escaping @MainActor @Sendable (KeyPress) -> KeyPressResult
    ) -> Self {
        var copy = self
        copy.resultKeyPress = action
        return copy
    }

    private var query: Binding<String> {
        let storage = externalQuery ?? $internalQuery
        return Binding(
            get: { storage.wrappedValue },
            set: { value in
                storage.wrappedValue = value
                // Filtering is a selection transition, not just presentation.
                // Commit both before another control can act on the selection.
                let ids = SearchMatcher.filtered(items, query: storage.wrappedValue, filter: filter,
                                                 searchText: searchText).map(\.id)
                selection.wrappedValue = SearchSelection.reconciled(selection.wrappedValue, visibleIDs: ids)
            }
        )
    }

    private func activateSelection() {
        // Input can arrive faster than frames. Reconcile from the current query,
        // not a result array captured before type-ahead changed that query.
        let current = SearchMatcher.filtered(items, query: query.wrappedValue,
                                             filter: filter, searchText: searchText)
        let id = SearchSelection.reconciled(selection.wrappedValue, visibleIDs: current.map(\.id))
        selection.wrappedValue = id
        if let item = current.first(where: { $0.id == id }) { activation?(item) }
    }
}

extension SearchableList: View {
    public var body: some View {
        let visible = SearchMatcher.filtered(items, query: query.wrappedValue, filter: filter, searchText: searchText)
        let visibleIDs = visible.map(\.id)
        let selectedID = SearchSelection.reconciled(selection.wrappedValue, visibleIDs: visibleIDs)
        // The projected getter presents the reconciled selection immediately;
        // lifecycle actions commit it back to the application's owned value.
        let visibleSelection = Binding<Item.ID?>(
            get: { SearchSelection.reconciled(selection.wrappedValue, visibleIDs: visibleIDs) },
            set: { selection.wrappedValue = $0 }
        )

        VStack(alignment: .leading, spacing: theme.spacing.sectionGap) {
            TextField(prompt, text: query)
                .focused($focus, equals: .search)
                .onKeyPress(.return) { _ in
                    focus = .results
                    return .handled
                }
                .onKeyPress(.escape) { _ in
                    query.wrappedValue = ""
                    focus = .results
                    return .handled
                }

            if visible.isEmpty {
                Text(items.isEmpty ? "No items yet." : "No matches. Clear the search to see all items.")
                    .foregroundStyle(theme.colors.secondaryText)
            }

            List(visible, selection: visibleSelection, onActivate: { id in
                guard let item = visible.first(where: { $0.id == id }) else { return }
                activation?(item)
            }) { item in
                HStack(alignment: .top, spacing: theme.spacing.horizontalInset) {
                    Text(item.id == selectedID ? theme.treatments.selectionMarker : " ")
                        .foregroundStyle(theme.colors.accent)
                    rowContent(item)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(theme.colors.foreground)
                .background(item.id == selectedID ? theme.colors.selectedSurface : theme.colors.surface)
            }
            // Selectable List containers normally focus their row identities.
            // Making the native container focusable gives search a stable
            // return target even when filtering leaves no rows.
            .focusable()
            .focused($focus, equals: .results)
            .onKeyPress(.return) { _ in
                activateSelection()
                return .handled
            }
            .onKeyPress(.character("/")) { _ in
                focus = .search
                return .handled
            }
            .onKeyPress(.escape) { _ in
                query.wrappedValue = ""
                return .handled
            }
            .onKeyPress { press in
                // A terminal read can contain '/' and subsequent text before
                // SwiftTUI commits the requested focus on its next frame. Carry
                // that type-ahead into the query instead of running shortcuts.
                // Once search owns focus, its native editor handles all input.
                if focus == .search {
                    guard press.modifiers.subtracting(.shift).isEmpty else { return .ignored }
                    switch press.key {
                    case .character(let character): query.wrappedValue.append(character)
                    case .space: query.wrappedValue.append(" ")
                    case .backspace:
                        if !query.wrappedValue.isEmpty { query.wrappedValue.removeLast() }
                    case .return: focus = .results
                    case .tab:
                        focus = .results
                        return .ignored
                    case .escape:
                        query.wrappedValue = ""
                        focus = .results
                    default: return .ignored
                    }
                    return .handled
                }
                return resultKeyPress?(press) ?? .ignored
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Text("\(visible.count) of \(items.count) \(items.count == 1 ? "item" : "items")")
                .foregroundStyle(theme.colors.mutedText)
        }
        .onAppear {
            focus = .results
        }
        .onChange(of: visibleIDs, initial: true) { _, ids in
            selection.wrappedValue = SearchSelection.reconciled(selection.wrappedValue, visibleIDs: ids)
        }
        .onChange(of: selection.wrappedValue) {
            let reconciled = SearchSelection.reconciled(selection.wrappedValue, visibleIDs: visibleIDs)
            if selection.wrappedValue != reconciled { selection.wrappedValue = reconciled }
        }
        .onChange(of: focus == .search, initial: true) {
            searchFocusChange?(focus == .search)
        }
    }
}
