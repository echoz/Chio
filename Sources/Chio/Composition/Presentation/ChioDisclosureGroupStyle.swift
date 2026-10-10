import SwiftTUIViews

/// A compact branch row with semantic expansion and keyboard-focus treatments.
/// Native disclosure groups retain expansion, activation and content ownership.
public struct ChioDisclosureGroupStyle {
    public let theme: ChioTheme

    public init(theme: ChioTheme = .default) {
        self.theme = theme
    }
}

extension ChioDisclosureGroupStyle: DisclosureGroupStyle {
    @MainActor
    public func makeBody(configuration: DisclosureGroupStyleConfiguration) -> some View {
        let isFocused = configuration.isEnabled && configuration.focusActive
        let isActive = configuration.isEnabled && (configuration.focusActive || configuration.isPressed)
        VStack(alignment: .leading, spacing: 0) {
            configuration.trigger {
                HStack(spacing: 1) {
                    Text(isFocused ? "▌" : " ").foregroundStyle(theme.colors.accent)
                    Text(configuration.isExpanded ? "▾" : "▸")
                        .foregroundStyle(configuration.isExpanded ? theme.colors.accent : theme.colors.mutedText)
                    configuration.label.foregroundStyle(theme.colors.foreground).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .background(isActive ? theme.colors.selectedSurface : Color.clear)
                .opacity(configuration.isEnabled ? 1 : 0.6)
            }
            // Align content with the label after the rail, glyph and two spaces.
            VStack(alignment: .leading, spacing: 0) {
                configuration.content
            }
            .padding(.leading, 4)
        }
    }
}

extension ChioDisclosureGroupStyle: Equatable {}
