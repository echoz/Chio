import SwiftTUIViews

/// Semantic colors, cell spacing, and visual treatments for a Chio subtree.
public struct ChioTheme {
    public var colors: Colors
    public var spacing: Spacing
    public var treatments: Treatments

    public init(
        colors: Colors = .init(),
        spacing: Spacing = .init(),
        treatments: Treatments = .init()
    ) {
        self.colors = colors
        self.spacing = spacing
        self.treatments = treatments
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
        public var accent: Color
        public var heading: Color
        public var foreground: Color
        public var secondaryText: Color
        public var mutedText: Color
        public var surface: Color
        public var selectedSurface: Color
        public var border: Color
        public var success: Color
        public var warning: Color
        public var error: Color

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
    }

    public struct Treatments {
        public var borderStyle: StrokeStyle
        /// A single-cell glyph shown beside the selected search result.
        public var selectionMarker: String {
            willSet { Self.requireSingleCellGlyph(newValue) }
        }
        /// Single-cell glyphs repeated across a progress track.
        public var progressFilledGlyph: String {
            willSet { Self.requireSingleCellGlyph(newValue) }
        }
        public var progressEmptyGlyph: String {
            willSet { Self.requireSingleCellGlyph(newValue) }
        }

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
extension ChioTheme.Colors: Sendable {}
extension ChioTheme.Spacing: Equatable {}
extension ChioTheme.Spacing: Sendable {}
extension ChioTheme.Treatments: Equatable {}
extension ChioTheme.Treatments: Sendable {}
