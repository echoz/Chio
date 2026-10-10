import Foundation
import SwiftTUIViews

/// A passive indication of a supplied measurement's position on its scale.
///
/// A known position must be finite and in `0...1`; `nil` means a missing reading,
/// distinct from zero. Applications own normalization, units, out-of-range policy
/// and surrounding labels. This view owns no clock, sampling or measurement state.
///
/// The bar uses one row; the dial uses up to five rows. Both adapt to the native
/// allocation, prefer twenty columns, and limit drawing to 512 columns. The
/// environment's accent color applies at every position, including one. Replace
/// the accessibility label to describe an application's scale and units.
@MainActor
public struct MeasurementGauge {
    @Environment(\.chioTheme) private var theme
    private let position: Double?
    private let style: Style

    /// The presentation of a measurement on a normalized scale.
    public enum Style {
        case bar
        case dial
    }

    public init(position: Double?, style: Style = .bar) {
        if let position {
            let isFinite = position.isFinite
            let isWithinScale = (0...1).contains(position)
            precondition(isFinite && isWithinScale,
                         "MeasurementGauge position must be finite and in 0...1; use nil for a missing reading.")
        }
        self.position = position
        self.style = style
    }

    private var preferredHeight: Int {
        switch style {
        case .bar: return 1
        case .dial: return 5
        }
    }

    private var summary: String {
        guard let position else { return "Measurement: missing reading." }
        return "Measurement position: \(position) of 1."
    }
}

extension MeasurementGauge.Style: Hashable {}
extension MeasurementGauge.Style: Sendable {}

extension MeasurementGauge: View {
    public var body: some View {
        Canvas(MeasurementDrawing(position: position, style: style), grid: .braille2x4)
            .frame(idealWidth: 20, maxWidth: 512,
                   idealHeight: .finite(preferredHeight), maxHeight: .finite(preferredHeight))
            .foregroundStyle(theme.colors.accent)
            .accessibilityLabel(summary)
    }
}

private struct MeasurementDrawing {
    let position: Double?
    let style: MeasurementGauge.Style

    private func drawBar(into context: inout CanvasContext, width: Int) {
        let filled = position.map { Int(($0 * Double(width)).rounded()) }
        for column in 0..<width {
            let glyph: Character
            if let filled {
                glyph = column < filled ? "▰" : "▱"
            } else {
                glyph = "·"
            }
            context.setCell(at: CellPoint(x: column, y: 0), character: glyph,
                            foreground: context.foreground)
        }
    }

    private func drawDial(into context: inout CanvasContext, width: Int) {
        let height = min(5, context.size.height)
        // A terminal cell is approximately twice as tall as it is wide. Separate
        // radii preserve the semicircle's aspect and fit even one-cell allocations.
        let radiusX = Double(width) / 2 - 0.25
        let radiusY = min(Double(height) - 0.25, radiusX / 2)
        let center = Point(x: Double(width) / 2, y: radiusY + 0.125)
        let steps = max(12, width * 4)
        var previous: Point?
        for index in 0...steps {
            let angle = Double.pi * (1 - Double(index) / Double(steps))
            let point = Point(x: center.x + cos(angle) * radiusX,
                              y: center.y - sin(angle) * radiusY)
            if let previous { context.line(from: previous, to: point) }
            else { context.setPixel(at: point) }
            previous = point
        }
        guard let position else { return }
        let angle = Double.pi * (1 - position)
        let tip = Point(x: center.x + cos(angle) * radiusX * 0.82,
                        y: center.y - sin(angle) * radiusY * 0.82)
        context.line(from: center, to: tip)
    }
}

extension MeasurementDrawing: CanvasDrawing {
    func draw(into context: inout CanvasContext) {
        guard context.size.width > 0, context.size.height > 0 else { return }
        let width = min(512, context.size.width)
        switch style {
        case .bar: drawBar(into: &context, width: width)
        case .dial: drawDial(into: &context, width: width)
        }
    }
}
