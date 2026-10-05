import SwiftTUIViews

/// Compact, themed elapsed or remaining time with a readable accessibility label.
///
/// Durations must be nonnegative and no greater than `Duration.seconds(Int64.max)`.
/// Elapsed time rounds down to whole seconds; positive remaining time rounds up,
/// so it never displays zero before expiry. Hours continue past 24 rather than wrap.
/// Scheduling, pause state and the meaning of expiry belong to the application.
@MainActor
public struct DurationText {
    private enum Kind {
        case elapsed
        case remaining
    }

    private let duration: Duration
    private let kind: Kind
    @Environment(\.chioTheme) private var theme

    public init(elapsed duration: Duration) {
        self.init(duration: duration, kind: .elapsed)
    }

    public init(remaining duration: Duration) {
        self.init(duration: duration, kind: .remaining)
    }

    private init(duration: Duration, kind: Kind) {
        precondition(duration >= .zero && duration <= .seconds(Int64.max),
                     "DurationText requires a duration between zero and Int64.max seconds")
        self.duration = duration
        self.kind = kind
    }

    private var wholeSeconds: Int64 {
        let components = duration.components
        switch kind {
        case .elapsed: return components.seconds
        case .remaining:
            // The input bound ensures a fractional duration has room for this carry.
            return components.seconds + (components.attoseconds > 0 ? 1 : 0)
        }
    }

    private var compactText: String {
        let seconds = wholeSeconds
        let hours = seconds / 3_600
        let minutes = seconds / 60 % 60
        let tail = Self.twoDigits(seconds % 60)
        if hours > 0 { return "\(hours):\(Self.twoDigits(minutes)):\(tail)" }
        return "\(minutes):\(tail)"
    }

    private var spokenText: String {
        let seconds = wholeSeconds
        let hours = seconds / 3_600
        let minutes = seconds / 60 % 60
        let remainder = seconds % 60
        var units: [String] = []
        if hours > 0 { units.append(Self.spoken(hours, unit: "hour")) }
        if minutes > 0 { units.append(Self.spoken(minutes, unit: "minute")) }
        if remainder > 0 || units.isEmpty { units.append(Self.spoken(remainder, unit: "second")) }
        let prefix: String
        switch kind {
        case .elapsed: prefix = "Elapsed time"
        case .remaining: prefix = "Remaining time"
        }
        return "\(prefix): \(units.joined(separator: ", "))"
    }

    private static func twoDigits(_ value: Int64) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

    private static func spoken(_ value: Int64, unit: String) -> String {
        "\(value) \(unit)\(value == 1 ? "" : "s")"
    }
}

extension DurationText: View {
    public var body: some View {
        Text(verbatim: compactText)
            .foregroundStyle(theme.colors.accent)
            .accessibilityLabel(spokenText)
    }
}
