import SwiftTUIViews

/// A compact bordered action with visible focus and destructive-role colors.
public struct ChioButtonStyle {
    public var theme: ChioTheme

    public init(theme: ChioTheme = .default) {
        self.theme = theme
    }
}

extension ChioButtonStyle: ButtonStyle {
    @MainActor
    public func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        let active = configuration.isEnabled && (configuration.focusActive || configuration.isPressed)
        let tone = configuration.role == .destructive ? theme.colors.error : theme.colors.accent
        configuration.label
            .padding(.horizontal, theme.spacing.horizontalInset)
            .foregroundStyle(configuration.isEnabled ? theme.colors.foreground : theme.colors.mutedText)
            .background(active ? theme.colors.selectedSurface : theme.colors.surface)
            .border(active ? tone : theme.colors.border,
                    style: theme.treatments.borderStyle, placement: .outset)
            .opacity(configuration.isEnabled ? 1 : 0.6)
    }
}

extension ChioButtonStyle: Equatable {}
