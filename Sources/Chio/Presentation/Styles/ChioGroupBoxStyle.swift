import SwiftTUIViews

/// A heading above padded content with rounded terminal chrome.
public struct ChioGroupBoxStyle {
    public let theme: ChioTheme

    public init(theme: ChioTheme = .default) {
        self.theme = theme
    }
}

extension ChioGroupBoxStyle: GroupBoxStyle {
    @MainActor
    public func makeBody(configuration: GroupBoxStyleConfiguration) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.sectionGap) {
            if let label = configuration.label {
                label.foregroundStyle(theme.colors.heading)
            }
            configuration.content
        }
        .padding(.init(horizontal: theme.spacing.horizontalInset, vertical: theme.spacing.verticalInset))
        .foregroundStyle(theme.colors.foreground)
        .background(theme.colors.surface)
        .border(
            configuration.controlProminence == .increased ? theme.colors.accent : theme.colors.border,
            style: theme.treatments.borderStyle,
            placement: .outset
        )
    }
}

extension ChioGroupBoxStyle: Equatable {}
