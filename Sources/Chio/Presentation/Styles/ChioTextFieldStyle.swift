import SwiftTUIViews

/// A padded search field with an accent border while it owns focus.
public struct ChioTextFieldStyle {
    public let theme: ChioTheme

    public init(theme: ChioTheme = .default) {
        self.theme = theme
    }
}

extension ChioTextFieldStyle: TextFieldStyle {
    @MainActor
    public func makeBody(configuration: TextFieldStyleConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if configuration.showsLabel {
                configuration.label.foregroundStyle(theme.colors.secondaryText)
            }
            HStack(spacing: 0) {
                configuration.fieldContent
                    .foregroundStyle(configuration.isShowingPrompt ? theme.colors.mutedText : theme.colors.foreground)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, theme.spacing.horizontalInset)
            .background(theme.colors.surface)
            .border(configuration.focusActive && configuration.isEnabled ? theme.colors.accent : theme.colors.border,
                    style: theme.treatments.borderStyle, placement: .outset)
        }
        .opacity(configuration.isEnabled ? 1 : 0.6)
    }
}

extension ChioTextFieldStyle: Equatable {}
