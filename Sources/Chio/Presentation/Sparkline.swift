import SwiftTUIViews

/// Passive, single-series history drawn by SwiftTUI's braille canvas.
///
/// Samples run oldest to newest at equally spaced positions. `nil` is a missing
/// reading and breaks the line. Readings must be finite. Empty/all-missing input
/// draws nothing; a constant automatic series sits at the vertical midpoint.
/// A single-entry series is placed at the right edge. Fixed scales clip outliers.
///
/// Set a frame to choose the graph's size. Narrow drawings retain first, last,
/// minimum and maximum readings per drawing column within each uninterrupted
/// run. Gaps smaller than a drawing column may become visually indistinguishable,
/// but never introduce connecting segments. Input is scanned on each drawing;
/// applications own retention, sampling, timing, units and thresholds.
@MainActor
public struct Sparkline {
    @Environment(\.chioTheme) private var theme
    private let samples: [Double?]
    private let scale: Scale

    /// Scale configuration is checked when constructing the view.
    public enum Scale {
        case automatic
        /// Both endpoints must be finite, with the lower strictly below the upper.
        case fixed(ClosedRange<Double>)
    }

    public init(_ samples: [Double?], scale: Scale = .automatic) {
        precondition(samples.allSatisfy { $0?.isFinite ?? true }, "Sparkline readings must be finite; use nil for a gap.")
        switch scale {
        case .automatic: break
        case .fixed(let range):
            let hasFiniteLowerBound = range.lowerBound.isFinite
            let hasFiniteUpperBound = range.upperBound.isFinite
            let hasIncreasingBounds = range.lowerBound < range.upperBound
            precondition(hasFiniteLowerBound && hasFiniteUpperBound && hasIncreasingBounds,
                         "Sparkline fixed bounds must be finite and strictly increasing.")
        }
        self.samples = samples
        self.scale = scale
    }

    private var summary: String {
        let readings = samples.compactMap { $0 }
        guard let minimum = readings.min(), let maximum = readings.max() else {
            return "History: no readings, \(samples.count) missing."
        }
        let latest = samples.last.flatMap { $0 }.map { String($0) } ?? "unavailable"
        return "History: \(readings.count) readings, \(samples.count - readings.count) missing. Latest: \(latest). Minimum: \(minimum). Maximum: \(maximum)."
    }
}

extension Sparkline.Scale: Hashable {}
extension Sparkline.Scale: Codable {}
extension Sparkline.Scale: Sendable {}

extension Sparkline: View {
    public var body: some View {
        Canvas(HistoryDrawing(samples: samples, scale: scale), grid: .braille2x4)
            .foregroundStyle(theme.colors.accent)
            .accessibilityLabel(summary)
    }
}

private struct HistoryDrawing {
    let samples: [Double?]
    let scale: Sparkline.Scale

    private var bounds: ClosedRange<Double>? {
        switch scale {
        case let .fixed(range): range
        case .automatic:
            samples.compactMap { $0 }.min().flatMap { minimum in
                samples.compactMap { $0 }.max().map { minimum...$0 }
            }
        }
    }

    private func fraction(_ value: Double, in bounds: ClosedRange<Double>) -> Double {
        let lower = bounds.lowerBound
        let upper = bounds.upperBound
        guard lower < upper else { return 0.5 }
        if value <= lower { return 0 }
        if value >= upper { return 1 }
        let span = upper - lower
        if span.isFinite { return (value - lower) / span }
        // Finite endpoints can have an infinite difference. Scaling first keeps
        // the arithmetic finite without changing their relative positions.
        let magnitude = max(abs(lower), abs(upper))
        return (value / magnitude - lower / magnitude) / (upper / magnitude - lower / magnitude)
    }

    private struct Reading {
        let index: Int
        let value: Double
    }

    private struct Bucket {
        let column: Int
        let first: Reading
        let minimum: Reading
        let maximum: Reading
        let last: Reading

        init(column: Int, reading: Reading) {
            self.column = column
            first = reading
            minimum = reading
            maximum = reading
            last = reading
        }

        private init(column: Int, first: Reading, minimum: Reading, maximum: Reading, last: Reading) {
            self.column = column
            self.first = first
            self.minimum = minimum
            self.maximum = maximum
            self.last = last
        }

        func including(_ reading: Reading) -> Self {
            Bucket(column: column, first: first,
                 minimum: reading.value < minimum.value ? reading : minimum,
                 maximum: reading.value > maximum.value ? reading : maximum,
                 last: reading)
        }

        var readings: [Reading] {
            // Duplicates only produce zero-length native lines; avoiding a set
            // here also keeps ties in their original chronological order.
            [first, minimum, maximum, last].sorted { $0.index < $1.index }
        }
    }
}

extension HistoryDrawing: CanvasDrawing {
    func draw(into context: inout CanvasContext) {
        guard context.gridSize.width > 0, context.gridSize.height > 0,
              let bounds else { return }
        let lastColumn = context.gridSize.width - 1
        let lastRow = context.gridSize.height - 1
        var previous: Point?
        var bucket: Bucket?

        func column(at index: Int) -> Int {
            samples.count <= 1 ? lastColumn
                : min(lastColumn, Int(Double(index) / Double(samples.count - 1) * Double(lastColumn)))
        }

        func paint(_ bucket: Bucket, into context: inout CanvasContext, previous: inout Point?) {
            for reading in bucket.readings {
                let fraction = min(1, max(0, fraction(reading.value, in: bounds)))
                let row = min(lastRow, max(0, Int(((1 - fraction) * Double(lastRow)).rounded())))
                let point = Point(x: Double(bucket.column) / Double(context.grid.subdivisionsX),
                                  y: Double(row) / Double(context.grid.subdivisionsY))
                if let previous { context.line(from: previous, to: point) }
                else { context.setPixel(at: point) }
                previous = point
            }
        }

        for (index, value) in samples.enumerated() {
            guard let value else {
                if let pending = bucket { paint(pending, into: &context, previous: &previous) }
                bucket = nil
                previous = nil
                continue
            }
            let reading = Reading(index: index, value: value)
            let column = column(at: index)
            if let pending = bucket, pending.column == column {
                bucket = pending.including(reading)
            } else {
                if let pending = bucket { paint(pending, into: &context, previous: &previous) }
                bucket = Bucket(column: column, reading: reading)
            }
        }
        if let bucket { paint(bucket, into: &context, previous: &previous) }
    }
}
