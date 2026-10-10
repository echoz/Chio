import SwiftTUIViews

/// A compact result list that leaves selection, focus, and scrolling to SwiftTUI.
public struct ChioListStyle {
    public let theme: ChioTheme

    public init(theme: ChioTheme = .default) {
        self.theme = theme
    }
}

extension ChioListStyle: ListStyle {
    @MainActor
    public func resolvePresentation(for configuration: ListStyleConfiguration) -> ListStylePresentation {
        ListStylePresentation(
            contentInsets: EdgeInsets(top: 0, leading: theme.spacing.horizontalInset,
                                 bottom: 0, trailing: theme.spacing.horizontalInset),
            showsRowSeparators: false,
            showsSectionSeparators: false
        )
    }
}

extension ChioListStyle: Equatable {}
