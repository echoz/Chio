import SwiftTUIViews

/// A separated footer for contextual hints or application status.
@MainActor
public struct StatusBar<Content: View> {
    @Environment(\.chioTheme) private var theme
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
}

extension StatusBar: View {
    public var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            // Upstream Divider does not yet resolve ambient foreground paint.
            GeometryReader { geometry in
                Text(String(repeating: "─", count: max(0, geometry.size.width)))
                    .foregroundStyle(theme.colors.border)
            }
            .frame(height: 1)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
