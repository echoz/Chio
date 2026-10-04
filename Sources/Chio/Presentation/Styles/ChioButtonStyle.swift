import SwiftTUIViews

/// A compact action with an accent focus outline over its enclosing surface.
public struct ChioButtonStyle {
    public let theme: ChioTheme

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
            .border(active ? tone : theme.colors.border,
                    style: theme.treatments.borderStyle, placement: .outset)
            .opacity(configuration.isEnabled ? 1 : 0.6)
    }
}

extension ChioButtonStyle: Equatable {}
