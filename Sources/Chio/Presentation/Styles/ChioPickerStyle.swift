import SwiftTUIViews

/// A one-row selected value; native arrows and wheel input step through options.
public struct ChioPickerStyle {
    public let theme: ChioTheme
    public let showsLabel: Bool

    public init(theme: ChioTheme = .default, showsLabel: Bool = true) {
        self.theme = theme
        self.showsLabel = showsLabel
    }
}

extension ChioPickerStyle: PickerStyle {
    @MainActor
    public func selectionDelta(for event: KeyEvent) -> Int? {
        switch event {
        case .arrowUp, .arrowLeft: -1
        case .arrowDown, .arrowRight: 1
        default: nil
        }
    }

    @MainActor
    public func makeBody(configuration: PickerStyleConfiguration) -> some View {
        let active = configuration.focusActive && configuration.isEnabled
        HStack(spacing: 1) {
            Text(active ? "▌" : " ")
                .foregroundStyle(theme.colors.accent)
            if showsLabel {
                configuration.label.foregroundStyle(theme.colors.secondaryText)
            }
            Text("◂").foregroundStyle(active ? theme.colors.accent : theme.colors.mutedText)
            Text(configuration.selectedIndex.map { configuration.options[$0].label } ?? "Choose…")
                .foregroundStyle(configuration.selectedIndex == nil
                    ? theme.colors.mutedText : theme.colors.foreground)
                .lineLimit(1)
            Text("▸").foregroundStyle(active ? theme.colors.accent : theme.colors.mutedText)
            Spacer(minLength: 0)
        }
        .background(active ? theme.colors.selectedSurface : theme.colors.surface)
        .opacity(configuration.isEnabled ? 1 : 0.6)
    }
}

extension ChioPickerStyle: Equatable {}
