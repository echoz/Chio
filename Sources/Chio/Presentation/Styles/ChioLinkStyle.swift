import SwiftTUIViews

/// Underlined native links with semantic colors and a focused text surface.
public struct ChioLinkStyle {
    public let theme: ChioTheme

    public init(theme: ChioTheme = .default) {
        self.theme = theme
    }
}

extension ChioLinkStyle: LinkStyle {
    @MainActor
    public func resolvePresentation(for configuration: LinkStyleConfiguration) -> LinkStylePresentation {
        let isActive = configuration.isEnabled && (configuration.focusActive || configuration.isPressed)
        return LinkStylePresentation(
            foregroundStyle: AnyShapeStyle(configuration.isEnabled ? theme.colors.accent : theme.colors.mutedText),
            backgroundStyle: isActive ? AnyShapeStyle(theme.colors.selectedSurface) : nil,
            emphasis: isActive ? .bold : [],
            underline: .visible(TextLineStyle()),
            opacity: configuration.isEnabled ? 1 : 0.6
        )
    }
}

extension ChioLinkStyle: Equatable {}
