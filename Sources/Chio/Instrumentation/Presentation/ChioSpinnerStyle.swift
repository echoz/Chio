import SwiftTUIViews

/// Semantic paint around SwiftTUI's native braille spinner and cadence.
/// The native control owns animation, stage semantics, and reduced motion.
public struct ChioSpinnerStyle {
    public let theme: ChioTheme

    public init(theme: ChioTheme = .default) {
        self.theme = theme
    }
}

extension ChioSpinnerStyle: SpinnerStyle {
    @MainActor
    public func resolvePresentation(for configuration: SpinnerStyleConfiguration) -> SpinnerStylePresentation {
        let native = GlyphSpinnerStyle.automatic.resolvePresentation(for: configuration)
        let color: Color
        switch configuration.stage {
        case .inactive: color = theme.colors.mutedText
        case .active: color = theme.colors.accent
        case .finished: color = theme.colors.success
        }
        return SpinnerStylePresentation(
            activeFrames: native.activeFrames,
            inactiveFrame: "·",
            finishedFrame: "✓",
            interval: native.interval,
            foregroundStyle: AnyShapeStyle(color)
        )
    }
}

extension ChioSpinnerStyle: Equatable {}
