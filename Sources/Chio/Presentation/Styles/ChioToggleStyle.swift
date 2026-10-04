import SwiftTUIViews

/// A compact native toggle with a textual state and visible keyboard focus.
public struct ChioToggleStyle {
    public let theme: ChioTheme
    public let showsLabel: Bool

    public init(theme: ChioTheme = .default, showsLabel: Bool = true) {
        self.theme = theme
        self.showsLabel = showsLabel
    }
}

extension ChioToggleStyle: ToggleStyle {
    @MainActor
    public func makeBody(configuration: ToggleStyleConfiguration) -> some View {
        let active = configuration.isEnabled && (configuration.focusActive || configuration.isPressed)
        HStack(spacing: 1) {
            Text(configuration.focusActive && configuration.isEnabled ? "▌" : " ")
                .foregroundStyle(theme.colors.accent)
            Text(configuration.isMixed ? "[−]" : configuration.isOn ? "[✓]" : "[ ]")
                .foregroundStyle(configuration.isOn ? theme.colors.success : theme.colors.mutedText)
            Text(configuration.isMixed ? "Mixed" : configuration.isOn ? "On" : "Off")
                .foregroundStyle(theme.colors.foreground)
            if showsLabel {
                configuration.label.foregroundStyle(theme.colors.secondaryText).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .background(active ? theme.colors.selectedSurface : theme.colors.surface)
        .opacity(configuration.isEnabled ? 1 : 0.6)
    }
}

extension ChioToggleStyle: Equatable {}
