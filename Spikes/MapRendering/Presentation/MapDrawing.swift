import Chio
import Foundation
import SwiftTUI

/// Experimental geographic drawing; SwiftTUI packs samples and emits terminal cells.
/// Filled areas use cell backgrounds, keeping road/coastline braille visible above them.
struct MapDrawing {
    let map: PreparedMap
    let viewport: MapViewport
    let colors: ChioTheme.Colors
    let waterColor: Color
    let parkColor: Color
    let fills: Bool
    let work: MapDrawingWork

    init(map: PreparedMap, viewport: MapViewport, colors: ChioTheme.Colors,
         waterColor: Color, parkColor: Color, fills: Bool) throws {
        let work = try MapDrawingWork(map: map, viewport: viewport, fills: fills)
        self.map = map
        self.viewport = viewport
        self.colors = colors
        self.waterColor = waterColor
        self.parkColor = parkColor
        self.fills = fills
        self.work = work
    }

    private var columns: Int { viewport.columns }
    private var rows: Int { viewport.rows }

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

    /// Intersect a bounded scanline with the prepared rings. Pairing sorted crossings
    /// applies even-odd holes; fill and outline use the same prepared geometry.
    private func intervals(_ rings: [[PreparedMap.Point]], at y: Double) -> [(Double, Double)] {
        var crossings: [Double] = []
        for ring in rings {
            for (a, b) in zip(ring, ring.dropFirst()) where (a.y > y) != (b.y > y) {
                let x = a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x)
                // Floating-point cancellation can push an interpolated crossing
                // beyond its endpoints. Keep it inside the geometry used by preflight.
                if x.isFinite { crossings.append(min(max(a.x, b.x), max(min(a.x, b.x), x))) }
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
            let segment = MapDrawingWork.StrokeSegment(a, b, viewport: viewport)
            for step in 0...segment.steps {
                let fraction = Double(step) / Double(segment.steps)
                context.setPixel(at: Point(x: segment.x0 + (segment.x1 - segment.x0) * fraction,
                                           y: segment.y0 + (segment.y1 - segment.y0) * fraction), foreground: color)
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
                let bounds = MapDrawingWork.fillBounds(polygon.rings, viewport: viewport)
                for row in bounds.rows {
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
