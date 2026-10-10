import SwiftTUIViews

extension View {
    /// Scopes a theme and installs Chio's native control styles.
    public func chioTheme(_ theme: ChioTheme) -> some View {
        environment(\.chioTheme, theme)
            .groupBoxStyle(ChioGroupBoxStyle(theme: theme))
            .disclosureGroupStyle(ChioDisclosureGroupStyle(theme: theme))
            .listStyle(ChioListStyle(theme: theme))
            .tableStyle(ChioTableStyle(theme: theme))
            .tabViewStyle(ChioTabViewStyle(theme: theme))
            .scrollViewStyle(ChioScrollViewStyle(theme: theme))
            .paletteStyle(ChioPaletteStyle(theme: theme))
            .textFieldStyle(ChioTextFieldStyle(theme: theme))
            .textEditorStyle(ChioTextEditorStyle(theme: theme))
            .progressViewStyle(ChioProgressViewStyle(theme: theme))
            .spinnerStyle(ChioSpinnerStyle(theme: theme))
            .promptStyle(ChioPromptStyle(theme: theme))
            .buttonStyle(ChioButtonStyle(theme: theme))
            .linkStyle(ChioLinkStyle(theme: theme))
            .pickerStyle(ChioPickerStyle(theme: theme))
            .toggleStyle(ChioToggleStyle(theme: theme))
            .foregroundStyle(theme.colors.foreground)
            .tint(theme.colors.accent)
            .background(theme.colors.surface)
    }
}
