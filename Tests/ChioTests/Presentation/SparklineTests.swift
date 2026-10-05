import Chio
import SwiftTUIRuntime
import Testing

@MainActor
struct SparklineTests {
    private func render(_ values: [Double?], scale: Sparkline.Scale = .automatic,
                        width: Int = 5, height: Int = 2) -> RenderSnapshot {
        DefaultRenderer().render(Sparkline(values, scale: scale).frame(width: width, height: height),
                                 proposal: .init(width: width, height: height))
    }

    // Decode the public braille raster rather than inspecting private reduction.
    private func pixels(_ result: RenderSnapshot) -> Set<CellPoint> {
        let dots = [(0, 0), (0, 1), (0, 2), (1, 0), (1, 1), (1, 2), (0, 3), (1, 3)]
        var points: Set<CellPoint> = []
        for (y, row) in result.rasterSurface.lines.enumerated() {
            for (x, character) in row.enumerated() {
                guard let scalar = character.unicodeScalars.first,
                      (0x2800...0x28FF).contains(scalar.value) else { continue }
                let mask = scalar.value - 0x2800
                for (bit, dot) in dots.enumerated() where mask & (1 << bit) != 0 {
                    points.insert(.init(x: x * 2 + dot.0, y: y * 4 + dot.1))
                }
            }
        }
        return points
    }

    @Test("Empty and missing series leave the canvas blank, including zero allocations")
    func empty() {
        for size in [0, 1, 5] {
            for values in [[], [nil, nil]] as [[Double?]] {
                #expect(pixels(render(values, width: size, height: size)).isEmpty)
            }
        }
    }

    @Test("Automatic scale spans extrema; singleton is right aligned and constants are centered")
    func automatic() {
        #expect(pixels(render([42])) == [.init(x: 9, y: 4)])
        let constant = pixels(render([3, 3, 3]))
        #expect(constant.count == 10)
        #expect(constant.allSatisfy { $0.y == 4 })
        let rising = pixels(render([-20, 0, 20]))
        #expect(rising.contains(.init(x: 0, y: 7)))
        #expect(rising.contains(.init(x: 9, y: 0)))
    }

    @Test("Gaps occupy time slots and disconnect segments, including inside one reduced column")
    func gaps() {
        #expect(pixels(render([0, nil, 1], scale: .fixed(0...1)))
                == [.init(x: 0, y: 7), .init(x: 9, y: 0)])
        let narrow = pixels(render([0, nil, 1, nil, 0], scale: .fixed(0...1), width: 1))
        #expect(narrow == [.init(x: 0, y: 7), .init(x: 0, y: 0), .init(x: 1, y: 7)])
    }

    @Test("Dense histories keep a brief spike and trough at narrow widths")
    func reduction() {
        let values: [Double?] = (0..<100).map { $0 == 30 ? 100 : $0 == 31 ? 0 : 50 }
        for width in [1, 2, 8] {
            let points = pixels(render(values, scale: .fixed(0...100), width: width))
            #expect(points.contains { $0.y == 0 })
            #expect(points.contains { $0.y == 7 })
            #expect(points.allSatisfy { $0.x >= 0 && $0.x < width * 2 && $0.y >= 0 && $0.y < 8 })
        }
    }

    @Test("Finite extreme and subnormal scales render safely; fixed outliers clip")
    func numericalLimits() {
        let greatest = Double.greatestFiniteMagnitude
        let extreme = pixels(render([-greatest, 0, greatest]))
        #expect(extreme.contains(.init(x: 0, y: 7)))
        #expect(extreme.contains(.init(x: 9, y: 0)))
        let tiny = Double.leastNonzeroMagnitude
        #expect(pixels(render([0, tiny, tiny * 2])) == pixels(render([0, 1, 2])))
        #expect(pixels(render([-greatest, greatest], scale: .fixed(0...100)))
                == pixels(render([0, 100], scale: .fixed(0...100))))
    }

    @Test("Theme and accessible summary are passive; callers can name units")
    func semantics() {
        let theme = ChioTheme.btop
        let frame = DefaultRenderer().render(
            Sparkline([1, nil, 3]).frame(width: 10, height: 2).chioTheme(theme),
            proposal: .init(width: 10, height: 2))
        #expect(frame.semanticSnapshot.focusRegions.isEmpty)
        #expect(frame.semanticSnapshot.accessibilityNodes.contains {
            $0.label == "History: 2 readings, 1 missing. Latest: 3.0. Minimum: 1.0. Maximum: 3.0."
        })
        let painted = frame.rasterSurface.cells.flatMap { $0 }.filter { $0.character != " " }
        #expect(!painted.isEmpty)
        #expect(painted.allSatisfy { $0.style?.foregroundColor == theme.colors.accent })
        #expect(render([1, nil]).semanticSnapshot.accessibilityNodes.contains {
            $0.label?.contains("Latest: unavailable") == true
        })
        let labeled = DefaultRenderer().render(
            Sparkline([1]).accessibilityLabel("CPU history in percent").frame(width: 4, height: 1),
            proposal: .init(width: 4, height: 1))
        #expect(labeled.semanticSnapshot.accessibilityNodes.contains { $0.label == "CPU history in percent" })
    }

    @Test("The construction boundary rejects invalid readings and fixed scales")
    func invalidInput() async {
        await #expect(processExitsWith: .failure) {
            await MainActor.run { _ = Sparkline([.nan]) }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run { _ = Sparkline([.infinity]) }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run { _ = Sparkline([], scale: .fixed(1...1)) }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run { _ = Sparkline([], scale: .fixed(0...Double.infinity)) }
        }
    }
}
