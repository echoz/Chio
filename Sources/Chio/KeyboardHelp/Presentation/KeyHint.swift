import SwiftTUIViews

/// A consistently styled key label and the action it describes.
@MainActor
public struct KeyHint {
    @Environment(\.chioTheme) private var theme
    private let shortcut: ShortcutHint

    public init(_ key: String, _ label: String) {
        self.shortcut = ShortcutHint(key, label)
    }

    /// Displays the key and label; expanded details belong in `KeyboardHelp`.
    public init(_ shortcut: ShortcutHint) {
        self.shortcut = shortcut
    }
}

extension KeyHint: View {
    public var body: some View {
        var interpolation = Text.StringInterpolation(literalCapacity: 1, interpolationCount: 2)
        interpolation.appendInterpolation(Text(verbatim: shortcut.key).bold().foregroundStyle(theme.colors.accent))
        interpolation.appendLiteral(" ")
        interpolation.appendInterpolation(Text(verbatim: shortcut.label).foregroundStyle(theme.colors.secondaryText))
        return Text(Text.RichContent(stringInterpolation: interpolation))
    }
}
