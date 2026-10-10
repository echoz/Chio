import SwiftTUIViews

/// Passive, themed presentation of an application-formatted numeric value.
///
/// Segmented lettering uses three terminal rows for digits, decimal points,
/// colons and signs. Unsupported, empty or longer-than-32-character values use
/// ordinary text, as do allocations too small for the complete lettering.
/// Formatting, units, timing and interpretation remain with the application.
@MainActor
public struct InstrumentReadout {
    /// Presentation shared by numeric readouts and duration text.
    public enum Style {
        case plain
        case segmented
    }

    @Environment(\.chioTheme) private var theme
    private let value: String
    private let style: Style

    public init(_ value: String, style: Style = .segmented) {
        self.value = value
        self.style = style
    }

    private var segmentedText: String? {
        // Only the bounded prefix is inspected before deciding on the fallback.
        let characters = Array(value.prefix(33))
        guard !characters.isEmpty, characters.count <= 32 else { return nil }
        let glyphs = characters.compactMap { Self.font[$0] }
        guard glyphs.count == characters.count else { return nil }
        return (0..<3).map { row in
            glyphs.map { $0[row] }.joined(separator: " ")
        }.joined(separator: "\n")
    }

    private static let font: [Character: [String]] = [
        "0": [" _ ", "| |", "|_|"], "1": ["   ", "  |", "  |"],
        "2": [" _ ", " _|", "|_ "], "3": [" _ ", " _|", " _|"],
        "4": ["   ", "|_|", "  |"], "5": [" _ ", "|_ ", " _|"],
        "6": [" _ ", "|_ ", "|_|"], "7": [" _ ", "  |", "  |"],
        "8": [" _ ", "|_|", "|_|"], "9": [" _ ", "|_|", " _|"],
        ".": [" ", " ", "."], ":": [" ", ".", "."],
        "-": ["   ", " _ ", "   "], "+": ["   ", "_|_", " | "],
    ]
}

extension InstrumentReadout.Style: Hashable {}
extension InstrumentReadout.Style: Sendable {}

extension InstrumentReadout: View {
    public var body: some View {
        presentation
            .foregroundStyle(theme.colors.accent)
            .accessibilityLabel(value)
    }

    @ViewBuilder
    private var presentation: some View {
        switch style {
        case .plain:
            Text(verbatim: value)
        case .segmented:
            if let segmentedText {
                ViewThatFits {
                    Text(verbatim: segmentedText).lineLimit(nil).fixedSize()
                    Text(verbatim: value)
                }
            } else {
                Text(verbatim: value)
            }
        }
    }
}
