import SwiftTUIViews

/// Compact themed chrome for native alerts and confirmation dialogs.
/// SwiftTUI retains header paint, placement, action behavior, and modal focus.
public struct ChioPromptStyle {
    public let theme: ChioTheme

    public init(theme: ChioTheme = .default) {
        self.theme = theme
    }
}

extension ChioPromptStyle: PromptStyle {
    @MainActor
    public func resolvePresentation(for configuration: PromptStyleConfiguration) -> PromptSurfaceStylePresentation {
        var presentation = configuration.defaultPresentation
        let width = max(1, min(52, configuration.terminalSize.width - 2))
        let horizontal = min(theme.spacing.horizontalInset, max(0, (width - 4) / 2))
        // Native borders overlay the outer cells; reserve a row for the header.
        let vertical = max(1, min(theme.spacing.verticalInset, max(1, (configuration.terminalSize.height - 12) / 2)))
        let viewport = max(1, min(6, configuration.terminalSize.height - 10 - 2 * vertical))
        presentation.minimumWidth = min(presentation.minimumWidth, width)
        presentation.maximumWidth = width
        presentation.scrollMinimumHeight = 1
        presentation.scrollIdealHeight = min(4, viewport)
        presentation.scrollMaximumHeight = viewport
        presentation.contentInsets = EdgeInsets(horizontal: horizontal, vertical: vertical)
        presentation.backgroundStyle = AnyShapeStyle(theme.colors.surface)
        presentation.borderStyle = AnyShapeStyle(theme.colors.accent)
        presentation.borderStroke = theme.treatments.borderStyle
        return presentation
    }
}

extension ChioPromptStyle: Equatable {}
