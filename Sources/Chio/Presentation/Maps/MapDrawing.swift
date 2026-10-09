import Foundation
import SwiftTUIViews

/// Geographic drawing; SwiftTUI packs samples and emits terminal cells.
/// Filled areas use cell backgrounds, keeping road/coastline braille visible above them.
struct MapDrawing {
    let map: PreparedMap
    let viewport: MapViewport
    let colors: ChioTheme.Colors
    let waterColor: Color
    let parkColor: Color
    let fills: Bool
    let work: MapDrawingWork
    let routes: [PreparedMap.Line]
    let markers: [MapMarkerPlacement.Marker]

    init(prepared: PreparedMapDrawing, colors: ChioTheme.Colors, waterColor: Color, parkColor: Color,
         markers: [MapMarkerPlacement.Marker] = []) {
        map = prepared.map
        routes = prepared.routes
        viewport = prepared.viewport
        fills = prepared.fills
        work = prepared.work
        self.markers = markers
        self.colors = colors
        self.waterColor = waterColor
        self.parkColor = parkColor
    }

    init(map: PreparedMap, viewport: MapViewport, colors: ChioTheme.Colors,
         waterColor: Color, parkColor: Color, fills: Bool, routes: [PreparedMap.Line] = [],
         markers: [MapMarkerPlacement.Marker] = []) throws {
        let work = try MapDrawingWork(map: map, viewport: viewport, fills: fills, routes: routes)
        self.map = map
        self.viewport = viewport
        self.colors = colors
        self.waterColor = waterColor
        self.parkColor = parkColor
        self.fills = fills
        self.work = work
        self.routes = routes
        self.markers = markers
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
        case .water: colors.secondaryText
        case .park: colors.border
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
    /// Routes own every cell they touch: all eight dots share one foreground.
    /// One adjacent dot of clearance keeps pale geography from crowding the route.
    private func drawRoutes(into context: inout CanvasContext) {
        guard !routes.isEmpty else { return }
        var dots = BrailleCanvas(width: columns, height: rows)
        for line in routes {
            for (a, b) in zip(line.points, line.points.dropFirst()) {
                let segment = MapDrawingWork.StrokeSegment(a, b, viewport: viewport)
                for step in 0...segment.steps {
                    let t = Double(step) / Double(segment.steps)
                    dots.setPixel(x: Int(floor((segment.x0 + (segment.x1 - segment.x0) * t) * 2)),
                                  y: Int(floor((segment.y0 + (segment.y1 - segment.y0) * t) * 4)))
                }
            }
        }
        for y in 0..<rows {
            for x in 0..<columns where dots.cell(x: x, y: y).mask != 0 {
                clearDots(column: x, row: y, into: &context)
                for dy in 0..<4 {
                    for dx in 0..<2 where dots.cell(x: x, y: y).contains(x: dx, y: dy) {
                        for hy in -1...1 {
                            for hx in -1...1 {
                                context.clearSample(GridSample(x: x * 2 + dx + hx, y: y * 4 + dy + hy))
                            }
                        }
                    }
                }
            }
        }
        for y in 0..<dots.subpixelHeight {
            for x in 0..<dots.subpixelWidth where dots.cell(x: x / 2, y: y / 4).contains(x: x % 2, y: y % 4) {
                context.setPixel(at: Point(x: (Double(x) + 0.5) / 2, y: (Double(y) + 0.5) / 4),
                                 foreground: colors.accent)
            }
        }
    }

    private func clearDots(column: Int, row: Int, into context: inout CanvasContext) {
        for y in 0..<4 {
            for x in 0..<2 { context.clearSample(GridSample(x: column * 2 + x, y: row * 4 + y)) }
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
        drawRoutes(into: &context)
        // Native marker canvases paint later. Reserve only their lit cells, with
        // no extra marker halo: wider clearance detaches route endpoints.
        for marker in markers {
            for y in 0..<marker.glyph.height {
                for x in 0..<marker.glyph.width where marker.glyph.cell(x: x, y: y).mask != 0 {
                    clearDots(column: marker.origin.x + x, row: marker.origin.y + y, into: &context)
                }
            }
        }
    }
}
