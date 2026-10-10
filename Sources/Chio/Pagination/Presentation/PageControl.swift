import SwiftTUIViews

/// Native page actions with an empty state and a summary of the visible items.
/// Left/Right and Home/End navigate only while one of these buttons has focus.
@MainActor
public struct PageControl {
    private let pagination: Binding<Pagination>
    @Environment(\.chioTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    public init(pagination: Binding<Pagination>) {
        self.pagination = pagination
    }

    private func move(_ transition: (Pagination) -> Pagination) {
        guard isEnabled else { return }
        // Read the retained binding on every event, including input batches and
        // application setters that reject or transform a proposed page change.
        let current = pagination.wrappedValue
        let next = transition(current)
        if next != current { pagination.wrappedValue = next }
    }
}

extension PageControl: View {
    public var body: some View {
        let current = pagination.wrappedValue
        VStack(spacing: 0) {
            HStack(spacing: 1) {
                Button("‹") { move { $0.movingToPreviousPage() } }
                    .accessibilityLabel("Previous page")
                    .disabled(!current.canGoBack)
                Text(current.pageIndex.map { "\($0 + 1) / \(current.pageCount)" } ?? "No pages")
                    .bold()
                    .foregroundStyle(current.pageIndex == nil ? theme.colors.mutedText : theme.colors.accent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)
                Button("›") { move { $0.movingToNextPage() } }
                    .accessibilityLabel("Next page")
                    .disabled(!current.canGoForward)
            }
            Text(current.itemRange.isEmpty ? "0 items"
                 : "\(current.itemRange.lowerBound + 1)–\(current.itemRange.upperBound) of \(current.totalCount)")
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .onKeyPress { press in
            guard isEnabled, press.modifiers.isEmpty else { return .ignored }
            switch press.key {
            case .arrowLeft: move { $0.movingToPreviousPage() }
            case .arrowRight: move { $0.movingToNextPage() }
            case .home: move { $0.movingToFirstPage() }
            case .end: move { $0.movingToLastPage() }
            default: return .ignored
            }
            return .handled
        }
    }
}
