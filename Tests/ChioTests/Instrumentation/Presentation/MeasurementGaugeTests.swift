import Chio
import SwiftTUIRuntime
import Testing

@MainActor
struct MeasurementGaugeTests {
    private func render(_ position: Double?, style: MeasurementGauge.Style = .bar,
                        width: Int = 20, height: Int = 5) -> RenderSnapshot {
        DefaultRenderer().render(MeasurementGauge(position: position, style: style),
                                 proposal: ProposedSize(width: width, height: height))
    }

    private func glyphs(_ frame: RenderSnapshot) -> String {
        String(frame.rasterSurface.cells.flatMap { $0 }.map(\.character).filter { $0 != " " })
    }

    // Inspect the public braille raster rather than the drawing's geometry helpers.
    private func pixels(_ frame: RenderSnapshot) -> Set<CellPoint> {
        let dots = [(0, 0), (0, 1), (0, 2), (1, 0), (1, 1), (1, 2), (0, 3), (1, 3)]
        var result: Set<CellPoint> = []
        for (y, row) in frame.rasterSurface.lines.enumerated() {
            for (x, character) in row.enumerated() {
                guard let scalar = character.unicodeScalars.first,
                      (0x2800...0x28FF).contains(scalar.value) else { continue }
                let mask = scalar.value - 0x2800
                for (bit, dot) in dots.enumerated() where mask & (1 << bit) != 0 {
                    result.insert(CellPoint(x: x * 2 + dot.0, y: y * 4 + dot.1))
                }
            }
        }
        return result
    }

    @Test("The segmented bar distinguishes zero, midpoint, upper endpoint and missing readings")
    func barPositions() {
        #expect(glyphs(render(0, width: 10)) == "▱▱▱▱▱▱▱▱▱▱")
        #expect(glyphs(render(0.5, width: 10)) == "▰▰▰▰▰▱▱▱▱▱")
        #expect(glyphs(render(1, width: 10)) == "▰▰▰▰▰▰▰▰▰▰")
        #expect(glyphs(render(nil, width: 10)) == "··········")
    }

    @Test("The missing dial preserves its arc; known positions add the correctly directed needle")
    func dialPositions() {
        let arc = pixels(render(nil, style: .dial))
        #expect(!arc.isEmpty)
        // A twenty-column, five-row semicircle reaches both ends and the top.
        #expect(arc.contains { $0.x == 0 && $0.y == 19 })
        #expect(arc.contains { $0.x == 39 && $0.y == 19 })
        #expect(arc.contains { $0.y == 0 })
        let needleSamples = [CellPoint(x: 10, y: 19), CellPoint(x: 20, y: 10), CellPoint(x: 30, y: 19)]
        for (position, sample) in zip([0.0, 0.5, 1.0], needleSamples) {
            let indicated = pixels(render(position, style: .dial))
            #expect(arc.isSubset(of: indicated))
            #expect(!arc.contains(sample))
            #expect(indicated.contains(sample))
            #expect(indicated.count > arc.count)
        }
    }

    @Test("Native proposals determine bar width, with a bounded drawing and useful ideal sizes")
    func allocation() {
        for width in [1, 3, 9, 27, 512] {
            let frame = render(0.5, width: width)
            let filled = Int((Double(width) / 2).rounded())
            let expected = String(repeating: "▰", count: filled)
                + String(repeating: "▱", count: width - filled)
            #expect(glyphs(frame) == expected)
        }
        #expect(glyphs(render(0.5, width: 700)).count == 512)
        let idealBar = DefaultRenderer().render(MeasurementGauge(position: 0))
        let idealDial = DefaultRenderer().render(MeasurementGauge(position: nil, style: .dial))
        #expect(idealBar.rasterSurface.size == CellSize(width: 20, height: 1))
        #expect(idealDial.rasterSurface.size == CellSize(width: 20, height: 5))
    }

    @Test("Zero allocations are empty; small caller frames retain a visible known zero")
    func narrowFrames() {
        for style in [MeasurementGauge.Style.bar, .dial] {
            #expect(glyphs(render(0, style: style, width: 0)).isEmpty)
            #expect(glyphs(render(0, style: style, height: 0)).isEmpty)
            for width in [1, 2, 3] {
                let frame = DefaultRenderer().render(
                    MeasurementGauge(position: 0, style: style).frame(width: width, height: 1),
                    proposal: ProposedSize(width: width, height: 1))
                #expect(frame.rasterSurface.size == CellSize(width: width, height: 1))
                #expect(!glyphs(frame).isEmpty)
                #expect(glyphs(frame).count <= width)
            }
        }
        for width in [2, 9, 36] {
            let drawing = pixels(render(0.5, style: .dial, width: width, height: 3))
            #expect(!drawing.isEmpty)
            #expect(drawing.allSatisfy { $0.x >= 0 && $0.x < width * 2 && $0.y >= 0 && $0.y < 12 })
        }
    }

    @Test("Every reading uses the environment accent without implying completion or adding focus")
    func themeAndSemantics() {
        for theme in [ChioTheme.default, .light, .btop] {
            for style in [MeasurementGauge.Style.bar, .dial] {
                for position in [0, 0.5, 1, nil] as [Double?] {
                    let frame = DefaultRenderer().render(
                        MeasurementGauge(position: position, style: style).chioTheme(theme),
                        proposal: ProposedSize(width: 20, height: 5))
                    let painted = frame.rasterSurface.cells.flatMap { $0 }.filter { $0.character != " " }
                    #expect(!painted.isEmpty)
                    #expect(painted.allSatisfy { $0.style?.foregroundColor == theme.colors.accent })
                    #expect(frame.semanticSnapshot.focusRegions.isEmpty)
                    #expect(!frame.semanticSnapshot.accessibilityNodes.contains { $0.role == .progressBar })
                    let expected: String
                    if let position { expected = "Measurement position: \(position) of 1." }
                    else { expected = "Measurement: missing reading." }
                    #expect(frame.semanticSnapshot.accessibilityNodes.contains {
                        $0.role == .image && $0.label == expected
                    })
                }
            }
        }
    }

    @Test("Callers can replace the default measurement label with scale and units")
    func accessibilityOverride() {
        for style in [MeasurementGauge.Style.bar, .dial] {
            let frame = DefaultRenderer().render(
                MeasurementGauge(position: 0.5, style: style)
                    .accessibilityLabel("Temperature: 18 degrees Celsius")
                    .frame(width: 20, height: 5),
                proposal: ProposedSize(width: 20, height: 5))
            let labels = frame.semanticSnapshot.accessibilityNodes.compactMap(\.label)
            #expect(labels.contains("Temperature: 18 degrees Celsius"))
            #expect(!labels.contains("Measurement position: 0.5 of 1."))
            #expect(frame.semanticSnapshot.focusRegions.isEmpty)
        }
    }

    @Test("Construction rejects nonfinite and out-of-scale positions")
    func invalidInput() async {
        await #expect(processExitsWith: .failure) {
            await MainActor.run { _ = MeasurementGauge(position: .nan) }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run { _ = MeasurementGauge(position: .infinity) }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run { _ = MeasurementGauge(position: -.infinity, style: .dial) }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run { _ = MeasurementGauge(position: -Double.leastNonzeroMagnitude) }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run { _ = MeasurementGauge(position: Double(1).nextUp, style: .dial) }
        }
    }
}
