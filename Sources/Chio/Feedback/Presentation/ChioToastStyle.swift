import SwiftTUIViews

/// Compact semantic chrome for a native toast notification.
/// Pass explicitly to `.toast(..., style:)`; SwiftTUI owns placement and dismissal.
public struct ChioToastStyle {
    public let theme: ChioTheme
    public let tone: TerminalTone

    public init(theme: ChioTheme = .default, tone: TerminalTone = .info) {
        self.theme = theme
        self.tone = tone
    }
}

extension ChioToastStyle: ToastStyle {
    @MainActor
    public func resolvePresentation(for configuration: ToastStyleConfiguration) -> ToastStylePresentation {
        let color: Color
        let icon: String
        switch tone {
        case .accent, .info: color = theme.colors.accent; icon = "ℹ"
        case .success: color = theme.colors.success; icon = "✓"
        case .warning: color = theme.colors.warning; icon = "⚠"
        case .danger: color = theme.colors.error; icon = "✗"
        case .neutral: color = theme.colors.secondaryText; icon = "·"
        }
        let width = configuration.terminalSize.width > 0 ? min(60, configuration.terminalSize.width) : 60
        let height = configuration.terminalSize.height > 0 ? min(5, configuration.terminalSize.height) : 5
        let inset = min(theme.spacing.horizontalInset, (width - 1) / 2)
        return ToastStylePresentation(
            icon: icon,
            iconStyle: AnyShapeStyle(color),
            backgroundStyle: AnyShapeStyle(theme.colors.surface),
            borderStyle: AnyShapeStyle(color),
            contentPadding: EdgeInsets(top: height >= 3 ? 1 : 0, leading: inset,
                                  bottom: height >= 3 ? 1 : 0, trailing: inset),
            minWidth: min(10, width), maxWidth: width,
            minHeight: min(3, height), idealHeight: min(3, height), maxHeight: height
        )
    }
}

extension ChioToastStyle: Equatable {}
