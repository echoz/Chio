import Chio
import Foundation
import SwiftTUI

/// Experimental geographic drawing; SwiftTUI packs samples and emits terminal cells.
/// Filled areas use cell backgrounds, keeping road/coastline braille visible above them.
struct MapDrawing {
    let map: PreparedMap
    let columns: Int
    let rows: Int
    let colors: ChioTheme.Colors
    let waterColor: Color
    let parkColor: Color
    let fills: Bool

    private func fillColor(_ kind: MapFeature.Kind) -> Color {
        switch kind {
        case .land: colors.selectedSurface
        case .water: waterColor
        case .park: parkColor
        case .building: colors.selectedSurface
        case .road, .primaryRoad: colors.surface
        }
    }

    private func strokeColor(_ kind: MapFeature.Kind) -> Color {
        switch kind {
        case .land: colors.secondaryText
        case .water: waterColor
        case .park: parkColor
        case .building: colors.border
        case .road: colors.mutedText
        case .primaryRoad: colors.foreground
        }
    }

    private func priority(_ kind: MapFeature.Kind) -> Int {
        switch kind {
        case .land: 0
        case .park: 1
        case .water: 2
        case .building: 3
        case .road: 4
        case .primaryRoad: 5
        }
    }

    /// Intersect a bounded scanline with original rings. Pairing sorted crossings
    /// applies even-odd holes without reconstructing or simplifying polygon topology.
    private func intervals(_ rings: [[PreparedMap.Point]], at y: Double) -> [(Double, Double)] {
        var crossings: [Double] = []
        for ring in rings {
            for (a, b) in zip(ring, ring.dropFirst()) where (a.y > y) != (b.y > y) {
                let x = a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x)
                if x.isFinite { crossings.append(x) }
            }
        }
        crossings.sort()
        return stride(from: 0, to: max(0, crossings.count - 1), by: 2).map {
            (max(0, crossings[$0]), min(Double(columns), crossings[$0 + 1]))
        }.filter { $0.0 < $0.1 }
    }

    private func stroke(_ points: [PreparedMap.Point], color: Color, into context: inout CanvasContext) {
        // Preparation clips segments. Clamp boundary samples inward before native
        // submission. No walk here can exceed the allocated 2x4 sample diagonal.
        for (a, b) in zip(points, points.dropFirst()) {
            let x0 = min(Double(columns) - 0.001, max(0, a.x))
            let y0 = min(Double(rows) - 0.001, max(0, a.y))
            let x1 = min(Double(columns) - 0.001, max(0, b.x))
            let y1 = min(Double(rows) - 0.001, max(0, b.y))
            let steps = max(1, Int(ceil(max(abs(x1 - x0) * 2, abs(y1 - y0) * 4))))
            for step in 0...steps {
                let fraction = Double(step) / Double(steps)
                context.setPixel(at: Point(x: x0 + (x1 - x0) * fraction,
                                           y: y0 + (y1 - y0) * fraction), foreground: color)
            }
        }
    }
}

extension MapDrawing: Equatable {}
extension MapDrawing: Sendable {}

extension MapDrawing: CanvasDrawing {
    func draw(into context: inout CanvasContext) {
        guard columns > 0, rows > 0 else { return }
        if fills {
            for polygon in map.polygons.sorted(by: { priority($0.kind) < priority($1.kind) }) {
                let color = fillColor(polygon.kind)
                for row in 0..<rows {
                    for (left, right) in intervals(polygon.rings, at: Double(row) + 0.5) {
                        let start = max(0, Int(ceil(left - 0.5)))
                        let end = min(columns, Int(ceil(right - 0.5)))
                        if start < end {
                            for column in start..<end {
                                context.fillCell(color, at: CellPoint(x: column, y: row))
                            }
                        }
                    }
                }
            }
        }
        for line in map.lines.sorted(by: { priority($0.kind) < priority($1.kind) }) {
            stroke(line.points, color: strokeColor(line.kind), into: &context)
        }
    }
}
