import SwiftTUIViews

/// A consistently styled key label and the action it describes.
@MainActor
public struct KeyHint {
    @Environment(\.chioTheme) private var theme
    private let key: String
    private let label: String

    public init(_ key: String, _ label: String) {
        self.key = key
        self.label = label
    }
}

extension KeyHint: View {
    public var body: some View {
        HStack(spacing: 1) {
            Text(key).bold().foregroundStyle(theme.colors.accent)
            Text(label).foregroundStyle(theme.colors.secondaryText)
        }
    }
}
