import SwiftTUIViews

/// A field heading, native control, and one wrapping helper or error message.
/// Empty descriptions are omitted; a present error replaces the description.
/// Keep focus and current validation rules in the application.
@MainActor
public struct FormField<Content: View> {
    @Environment(\.chioTheme) private var theme
    private let title: String
    private let description: String
    private let error: String?
    private let content: Content

    public init(
        _ title: String,
        description: String = "",
        error: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.description = description
        self.error = error
        self.content = content()
    }
}

extension FormField: View {
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).bold().foregroundStyle(theme.colors.heading)
            content
                .pickerStyle(ChioPickerStyle(theme: theme, showsLabel: false))
                .toggleStyle(ChioToggleStyle(theme: theme, showsLabel: false))
            if let error {
                Text("Error: \(error)").foregroundStyle(theme.colors.error)
            } else if !description.isEmpty {
                Text(description).foregroundStyle(theme.colors.secondaryText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
