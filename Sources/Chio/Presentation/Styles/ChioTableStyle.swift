import SwiftTUIViews

/// Native rounded table chrome with semantic header colors.
public struct ChioTableStyle {
    public let theme: ChioTheme

    public init(theme: ChioTheme = .default) {
        self.theme = theme
    }
}

extension ChioTableStyle: TableStyle {
    @MainActor
    public func resolvePresentation(for configuration: TableStyleConfiguration) -> TableStylePresentation {
        .init(
            borderGlyphs: .insetGrouped,
            headerForegroundStyle: AnyShapeStyle(theme.colors.heading),
            headerBackgroundStyle: AnyShapeStyle(theme.colors.selectedSurface),
            // The pinned SwiftTUI currently masks this with its native border paint.
            borderStyle: AnyShapeStyle(theme.colors.border)
        )
    }
}

extension ChioTableStyle: Equatable {}
