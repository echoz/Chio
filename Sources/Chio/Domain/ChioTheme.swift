import SwiftTUIViews

/// Semantic colors, cell spacing, and visual treatments for a Chio subtree.
public struct ChioTheme {
    public let colors: Colors
    public let spacing: Spacing
    public let treatments: Treatments

    public init(
        colors: Colors = .init(),
        spacing: Spacing = .init(),
        treatments: Treatments = .init()
    ) {
        self.colors = colors
        self.spacing = spacing
        self.treatments = treatments
    }

    /// Returns a new theme; omitted components retain their current values.
    public func replacing(
        colors: Colors? = nil,
        spacing: Spacing? = nil,
        treatments: Treatments? = nil
    ) -> Self {
        Self(colors: colors ?? self.colors, spacing: spacing ?? self.spacing,
             treatments: treatments ?? self.treatments)
    }

    /// A dark palette inspired by Charm's Huh controls and Bubbles lists.
    public static let `default` = ChioTheme()

    public static let light = ChioTheme(colors: .init(
        accent: Color(hexRGB: 0xB52B80),
        heading: Color(hexRGB: 0x5145CD),
        foreground: Color(hexRGB: 0x272634),
        secondaryText: Color(hexRGB: 0x565367),
        mutedText: Color(hexRGB: 0x777285),
        surface: Color(hexRGB: 0xFAF8FF),
        selectedSurface: Color(hexRGB: 0xE9E3FC),
        border: Color(hexRGB: 0xB4ACC4),
        success: Color(hexRGB: 0x23784E),
        warning: Color(hexRGB: 0x996800),
        error: Color(hexRGB: 0xBE354B)
    ))

    public struct Colors {
        public let accent: Color
        public let heading: Color
        public let foreground: Color
        public let secondaryText: Color
        public let mutedText: Color
        public let surface: Color
        public let selectedSurface: Color
        public let border: Color
        public let success: Color
        public let warning: Color
        public let error: Color

        public init(
            accent: Color = Color(hexRGB: 0xF780E2),
            heading: Color = Color(hexRGB: 0x7571F9),
            foreground: Color = Color(hexRGB: 0xF2EEFA),
            secondaryText: Color = Color(hexRGB: 0xBBB4CB),
            mutedText: Color = Color(hexRGB: 0x81778F),
            surface: Color = Color(hexRGB: 0x211D2A),
            selectedSurface: Color = Color(hexRGB: 0x3A2D4F),
            border: Color = Color(hexRGB: 0x554762),
            success: Color = Color(hexRGB: 0x02BF87),
            warning: Color = Color(hexRGB: 0xF4CA64),
            error: Color = Color(hexRGB: 0xED567A)
        ) {
            self.accent = accent
            self.heading = heading
            self.foreground = foreground
            self.secondaryText = secondaryText
            self.mutedText = mutedText
            self.surface = surface
            self.selectedSurface = selectedSurface
            self.border = border
            self.success = success
            self.warning = warning
            self.error = error
        }

        /// Returns a new palette; omitted colors retain their current values.
        public func replacing(
            accent: Color? = nil,
            heading: Color? = nil,
            foreground: Color? = nil,
            secondaryText: Color? = nil,
            mutedText: Color? = nil,
            surface: Color? = nil,
            selectedSurface: Color? = nil,
            border: Color? = nil,
            success: Color? = nil,
            warning: Color? = nil,
            error: Color? = nil
        ) -> Self {
            Self(accent: accent ?? self.accent, heading: heading ?? self.heading,
                 foreground: foreground ?? self.foreground,
                 secondaryText: secondaryText ?? self.secondaryText,
                 mutedText: mutedText ?? self.mutedText, surface: surface ?? self.surface,
                 selectedSurface: selectedSurface ?? self.selectedSurface,
                 border: border ?? self.border, success: success ?? self.success,
                 warning: warning ?? self.warning, error: error ?? self.error)
        }
    }

    /// Insets and gaps measured in terminal cells.
    public struct Spacing {
        public let horizontalInset: Int
        public let verticalInset: Int
        public let sectionGap: Int
        public let hintGap: Int

        public init(
            horizontalInset: Int = 1,
            verticalInset: Int = 0,
            sectionGap: Int = 1,
            hintGap: Int = 2
        ) {
            precondition(horizontalInset >= 0 && verticalInset >= 0 && sectionGap >= 0 && hintGap >= 0,
                         "Theme spacing must be nonnegative")
            self.horizontalInset = horizontalInset
            self.verticalInset = verticalInset
            self.sectionGap = sectionGap
            self.hintGap = hintGap
        }

        /// Returns checked spacing; omitted distances retain their current values.
        public func replacing(
            horizontalInset: Int? = nil,
            verticalInset: Int? = nil,
            sectionGap: Int? = nil,
            hintGap: Int? = nil
        ) -> Self {
            Self(horizontalInset: horizontalInset ?? self.horizontalInset,
                 verticalInset: verticalInset ?? self.verticalInset,
                 sectionGap: sectionGap ?? self.sectionGap, hintGap: hintGap ?? self.hintGap)
        }
    }

    public struct Treatments {
        public let borderStyle: StrokeStyle
        /// A single-cell glyph shown beside the selected search result.
        public let selectionMarker: String
        /// Single-cell glyphs repeated across a progress track.
        public let progressFilledGlyph: String
        public let progressEmptyGlyph: String

        public init(
            borderStyle: StrokeStyle = .rounded,
            selectionMarker: String = "›",
            progressFilledGlyph: String = "━",
            progressEmptyGlyph: String = "─"
        ) {
            Self.requireSingleCellGlyph(selectionMarker)
            Self.requireSingleCellGlyph(progressFilledGlyph)
            Self.requireSingleCellGlyph(progressEmptyGlyph)
            self.borderStyle = borderStyle
            self.selectionMarker = selectionMarker
            self.progressFilledGlyph = progressFilledGlyph
            self.progressEmptyGlyph = progressEmptyGlyph
        }

        /// Returns checked treatments; omitted values retain their current values.
        public func replacing(
            borderStyle: StrokeStyle? = nil,
            selectionMarker: String? = nil,
            progressFilledGlyph: String? = nil,
            progressEmptyGlyph: String? = nil
        ) -> Self {
            Self(borderStyle: borderStyle ?? self.borderStyle,
                 selectionMarker: selectionMarker ?? self.selectionMarker,
                 progressFilledGlyph: progressFilledGlyph ?? self.progressFilledGlyph,
                 progressEmptyGlyph: progressEmptyGlyph ?? self.progressEmptyGlyph)
        }

        private static func requireSingleCellGlyph(_ glyph: String) {
            let layout = layoutText(for: glyph, width: nil)
            let containsControl = glyph.unicodeScalars.contains {
                $0.properties.generalCategory == .control
                    || $0.properties.generalCategory == .lineSeparator
                    || $0.properties.generalCategory == .paragraphSeparator
            }
            precondition(!containsControl && layout.lines.count == 1
                         && layout.lines[0].clusters.count == 1 && layout.lines[0].cellWidth == 1,
                         "Theme glyphs must contain exactly one printable terminal cell")
        }
    }
}

extension ChioTheme: Equatable {}
extension ChioTheme: Sendable {}
extension ChioTheme.Colors: Equatable {}
extension ChioTheme.Colors: Hashable {}
extension ChioTheme.Colors: Encodable {}
extension ChioTheme.Colors: Decodable {}
extension ChioTheme.Colors: Sendable {}
extension ChioTheme.Spacing: Equatable {}
extension ChioTheme.Spacing: Hashable {}
extension ChioTheme.Spacing: Encodable {}
extension ChioTheme.Spacing: Decodable {
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let horizontalInset = try values.decode(Int.self, forKey: .horizontalInset)
        let verticalInset = try values.decode(Int.self, forKey: .verticalInset)
        let sectionGap = try values.decode(Int.self, forKey: .sectionGap)
        let hintGap = try values.decode(Int.self, forKey: .hintGap)
        let distances: [(CodingKeys, Int)] = [
            (.horizontalInset, horizontalInset), (.verticalInset, verticalInset),
            (.sectionGap, sectionGap), (.hintGap, hintGap),
        ]
        for (key, distance) in distances where distance < 0 {
            throw DecodingError.dataCorruptedError(
                forKey: key, in: values, debugDescription: "Theme spacing must be nonnegative"
            )
        }
        self.init(horizontalInset: horizontalInset, verticalInset: verticalInset,
                  sectionGap: sectionGap, hintGap: hintGap)
    }
}
extension ChioTheme.Spacing: Sendable {}
extension ChioTheme.Treatments: Equatable {}
extension ChioTheme.Treatments: Sendable {}
