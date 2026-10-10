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
