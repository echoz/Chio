import SwiftTUIViews

/// Muted native scroll indicators with an accent while their viewport owns focus.
/// Geometry, visibility, navigation and pointer input remain native.
public struct ChioScrollViewStyle {
    public let theme: ChioTheme

    public init(theme: ChioTheme = .default) {
        self.theme = theme
    }
}

extension ChioScrollViewStyle: ScrollViewStyle {
    @MainActor
    public func resolvePresentation(for configuration: ScrollViewStyleConfiguration) -> ScrollViewStylePresentation {
        ScrollViewStylePresentation(
            snapshotLabel: snapshotLabel,
            indicatorStyle: AnyShapeStyle(theme.colors.mutedText),
            focusedIndicatorStyle: AnyShapeStyle(configuration.isEnabled && configuration.showsFocusEffect
                ? theme.colors.accent : theme.colors.mutedText),
            opacity: configuration.isEnabled ? 1 : 0.6
        )
    }
}

extension ChioScrollViewStyle: Equatable {}
