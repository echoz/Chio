import SwiftTUIViews

/// A slim progress track driven by SwiftTUI's determinate value or animation phase.
public struct ChioProgressViewStyle {
    public let theme: ChioTheme
    public let treatment: Treatment

    public init(theme: ChioTheme = .default, treatment: Treatment = .progress) {
        self.theme = theme
        self.treatment = treatment
    }

    public enum Treatment: String {
        /// Completed tasks use the theme's success color.
        case progress
        /// Measurements retain the accent color at every fraction, including 100%.
        /// Applications own units, thresholds and alert policy.
        case measurement
    }
}

extension ChioProgressViewStyle: ProgressViewStyle {
    @MainActor
    public func makeBody(configuration: ProgressViewStyleConfiguration) -> some View {
        let width = max(1, configuration.barWidth)
        VStack(alignment: .leading, spacing: 0) {
            if configuration.label != nil || configuration.currentValueLabel != nil {
                HStack(spacing: 1) {
                    if let label = configuration.label {
                        label.foregroundStyle(theme.colors.secondaryText)
                    }
                    if let value = configuration.currentValueLabel {
                        Spacer(minLength: 0)
                        value.foregroundStyle(theme.colors.mutedText)
                    }
                }
            }
            if let fraction = configuration.fractionCompleted {
                let normalized = fraction.isFinite ? min(max(fraction, 0), 1) : 0
                let filled = Int((Double(width) * normalized).rounded())
                HStack(spacing: 0) {
                    Text(String(repeating: theme.treatments.progressFilledGlyph, count: filled))
                        .foregroundStyle(treatment == .progress && normalized == 1
                            ? theme.colors.success : theme.colors.accent)
                    Text(String(repeating: theme.treatments.progressEmptyGlyph, count: width - filled))
                        .foregroundStyle(theme.colors.border)
                }
            } else {
                let band = max(1, width / 3)
                let offset = configuration.accessibilityReduceMotion
                    ? (width - band) / 2
                    : Int(configuration.indeterminatePhase % UInt64(width - band + 1))
                HStack(spacing: 0) {
                    Text(String(repeating: theme.treatments.progressEmptyGlyph, count: offset))
                        .foregroundStyle(theme.colors.border)
                    Text(String(repeating: theme.treatments.progressFilledGlyph, count: band))
                        .foregroundStyle(theme.colors.accent)
                    Text(String(repeating: theme.treatments.progressEmptyGlyph, count: width - offset - band))
                        .foregroundStyle(theme.colors.border)
                }
            }
        }
    }
}

extension ChioProgressViewStyle: Equatable {}

extension ChioProgressViewStyle.Treatment: Hashable {}
extension ChioProgressViewStyle.Treatment: Codable {}
extension ChioProgressViewStyle.Treatment: Sendable {}
