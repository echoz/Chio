import SwiftTUIViews

private enum ChioThemeKey {}

extension ChioThemeKey: EnvironmentKey {
    static let defaultValue = ChioTheme.default
}

extension EnvironmentValues {
    public var chioTheme: ChioTheme {
        get { self[ChioThemeKey.self] }
        set { self[ChioThemeKey.self] = newValue }
    }
}

extension View {
    /// Scopes a theme and installs Chio's native control styles.
    public func chioTheme(_ theme: ChioTheme) -> some View {
        environment(\.chioTheme, theme)
            .groupBoxStyle(ChioGroupBoxStyle(theme: theme))
            .listStyle(ChioListStyle(theme: theme))
            .tableStyle(ChioTableStyle(theme: theme))
            .paletteStyle(ChioPaletteStyle(theme: theme))
            .textFieldStyle(ChioTextFieldStyle(theme: theme))
            .progressViewStyle(ChioProgressViewStyle(theme: theme))
            .buttonStyle(ChioButtonStyle(theme: theme))
            .pickerStyle(ChioPickerStyle(theme: theme))
            .toggleStyle(ChioToggleStyle(theme: theme))
            .foregroundStyle(theme.colors.foreground)
            .tint(theme.colors.accent)
            .background(theme.colors.surface)
    }
}
