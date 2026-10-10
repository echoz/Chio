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
        let isActive = configuration.isEnabled && (configuration.focusActive || configuration.isPressed)
        let indicator: String
        let status: String
        if configuration.isMixed {
            indicator = "[−]"
            status = "Mixed"
        } else if configuration.isOn {
            indicator = "[✓]"
            status = "On"
        } else {
            indicator = "[ ]"
            status = "Off"
        }
        return HStack(spacing: 1) {
            Text(configuration.focusActive && configuration.isEnabled ? "▌" : " ")
                .foregroundStyle(theme.colors.accent)
            Text(indicator)
                .foregroundStyle(configuration.isOn ? theme.colors.success : theme.colors.mutedText)
            Text(status)
                .foregroundStyle(theme.colors.foreground)
            if showsLabel {
                configuration.label.foregroundStyle(theme.colors.secondaryText).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .background(isActive ? theme.colors.selectedSurface : theme.colors.surface)
        .opacity(configuration.isEnabled ? 1 : 0.6)
    }
}

extension ChioToggleStyle: Equatable {}
