@testable import Chio
import Foundation
import SwiftTUIRuntime

/// An isolated style proof over existing prepared geometry. Native BrailleCanvas
/// owns masks; native Canvas owns glyphs and terminal cells. No public API changes.
struct BrailleMapDrawing {
    let viewport: MapViewport
    let cells: [Cell]
    let statistics: Statistics

    enum Treatment: String { case outlines, textured }

    // Explicit cell priority: a winning role never recolors another role's dots.
    enum Role: Int {
        case landTexture, parkTexture, waterTexture, outline, road, route, position

        var color: Color {
            switch self {
            case .landTexture: Color(hexRGB: 0x595266)
            case .parkTexture: Color(hexRGB: 0x73977E)
            case .waterTexture: Color(hexRGB: 0x668D9E)
            case .outline: ChioTheme.default.colors.secondaryText
            case .road: ChioTheme.default.colors.foreground
            case .route: ChioTheme.default.colors.accent
            case .position: ChioTheme.default.colors.warning
            }
        }
    }

    struct Cell {
        let column: Int
        let row: Int
        let dots: BrailleCell
        let role: Role
    }

    struct Statistics {
        let textureEdgeVisits: Int
        let textureSortWeight: Int
        let textureCandidates: Int
        let strokeSamples: Int
        let haloSamples: Int
        let mixedCellsBeforeResolution: Int
        /// Counts per-role dots, including coincident dots from different roles.
        let suppressedRoleDots: Int
    }

    init(map: PreparedMap, routes: [PreparedMap.Line], viewport: MapViewport,
         position: PreparedMap.Point?, treatment: Treatment) throws {
        // Validate all prepared geometry and bound the original DDA work first.
        let strokes = try MapDrawingWork(map: map, viewport: viewport, fills: false, routes: routes)
        let areaWork = try TextureWork(map: map, viewport: viewport, enabled: treatment == .textured)
        if let position, !position.x.isFinite || !position.y.isFinite {
            throw MapValidationError.invalidPath
        }
        let empty = BrailleCanvas(width: viewport.columns, height: viewport.rows)
        var masks = Array(repeating: empty, count: Role.allCases.count)
        if treatment == .textured {
            let owners = Self.textureOwners(map: map, viewport: viewport)
            for y in 0..<empty.subpixelHeight {
                for x in 0..<empty.subpixelWidth {
                    if let role = owners[y * empty.subpixelWidth + x], Self.hasTextureDot(role, x: x, y: y) {
                        masks[role.rawValue].setPixel(x: x, y: y)
                    }
                }
            }
        }
        for line in map.lines {
            let role: Role
            switch line.kind {
            case .primaryRoad: role = .road
            case .land, .water, .park, .building, .road: role = .outline
            }
            Self.stroke(line.points, viewport: viewport, into: &masks[role.rawValue])
        }
        for line in routes {
            Self.stroke(line.points, viewport: viewport, into: &masks[Role.route.rawValue])
        }
        if let position, position.x >= 0, position.y >= 0,
           position.x < Double(viewport.columns), position.y < Double(viewport.rows) {
            let x = Int(floor(position.x * 2)), y = Int(floor(position.y * 4))
            masks[Role.position.rawValue].strokeCircle(centerX: x, centerY: y, radius: 2)
            masks[Role.position.rawValue].setPixel(x: x, y: y)
        }

        let routeHalo = Self.halo(around: masks[Role.route.rawValue])
        let positionHalo = Self.halo(around: masks[Role.position.rawValue])
        var cells: [Cell] = []
        var collisions = 0, suppressed = 0
        for y in 0..<viewport.rows {
            for x in 0..<viewport.columns {
                let original = masks.map { $0.cell(x: x, y: y).mask }
                if original.filter({ $0 != 0 }).count > 1 { collisions += 1 }
                let positionMask = original[Role.position.rawValue]
                let routeMask = original[Role.route.rawValue]
                var surviving = original
                for role in Role.allCases where role != .position {
                    // Every marker-touched cell belongs to the marker; nearby dots
                    // are additionally cleared to make a small physical halo.
                    if positionMask != 0 { surviving[role.rawValue] = 0 }
                    else { surviving[role.rawValue] &= ~positionHalo.mask.cell(x: x, y: y).mask }
                    if role.rawValue < Role.route.rawValue {
                        if routeMask != 0 { surviving[role.rawValue] = 0 }
                        else { surviving[role.rawValue] &= ~routeHalo.mask.cell(x: x, y: y).mask }
                    }
                }
                if let role = Role.allCases.reversed().first(where: { surviving[$0.rawValue] != 0 }) {
                    let winner = surviving[role.rawValue]
                    cells.append(Cell(column: x, row: y, dots: BrailleCell(mask: winner), role: role))
                    suppressed += original.reduce(0) { $0 + $1.nonzeroBitCount } - winner.nonzeroBitCount
                } else {
                    suppressed += original.reduce(0) { $0 + $1.nonzeroBitCount }
                }
            }
        }
        self.viewport = viewport
        self.cells = cells
        statistics = Statistics(textureEdgeVisits: areaWork.edgeVisits,
                                textureSortWeight: areaWork.sortWeight,
                                textureCandidates: areaWork.candidates,
                                strokeSamples: strokes.strokeSamples,
                                haloSamples: routeHalo.samples + positionHalo.samples,
                                mixedCellsBeforeResolution: collisions, suppressedRoleDots: suppressed)
    }

    /// Same bounded DDA as the shipped renderer, including endpoint sampling.
    private static func stroke(_ points: [PreparedMap.Point], viewport: MapViewport,
                               into canvas: inout BrailleCanvas) {
        for (a, b) in zip(points, points.dropFirst()) {
            let segment = MapDrawingWork.StrokeSegment(a, b, viewport: viewport)
            for step in 0...segment.steps {
                let t = Double(step) / Double(segment.steps)
                canvas.setPixel(x: Int(floor((segment.x0 + (segment.x1 - segment.x0) * t) * 2)),
                                y: Int(floor((segment.y0 + (segment.y1 - segment.y0) * t) * 4)))
            }
        }
    }

    /// One dot of clearance, followed by whole-cell ownership at composition.
    /// At most 9 × 8 × columns × rows writes per halo, independent of path length.
    private static func halo(around source: BrailleCanvas) -> (mask: BrailleCanvas, samples: Int) {
        var output = BrailleCanvas(width: source.width, height: source.height)
        var samples = 0
        for y in 0..<source.subpixelHeight {
            for x in 0..<source.subpixelWidth where source.cell(x: x / 2, y: y / 4).contains(x: x % 2, y: y % 4) {
                for dy in -1...1 {
                    for dx in -1...1 {
                        output.setPixel(x: x + dx, y: y + dy)
                        samples += 1
                    }
                }
            }
        }
        return (output, samples)
    }

    /// Fixed screen-space stipple: no clock, randomness or provider-specific detail.
    private static func hasTextureDot(_ role: Role, x: Int, y: Int) -> Bool {
        switch role {
        case .waterTexture: y % 8 == 2 && x % 8 < 2
        case .parkTexture: y % 8 == 5 && (x + (y / 8) * 4) % 8 == 2
        case .landTexture: y % 8 == 5 && (x + (y / 8) * 4) % 8 == 5
        case .outline, .road, .route, .position: false
        }
    }

    /// Assign area ownership at dot centres before stippling, so water suppresses
    /// underlying land patterns but a polygon hole exposes the previous area.
    private static func textureOwners(map: PreparedMap, viewport: MapViewport) -> [Role?] {
        let width = viewport.columns * 2, height = viewport.rows * 4
        var owners = Array<Role?>(repeating: nil, count: width * height)
        // Match MapDrawing's fill order, which differs from feature admission order.
        for polygon in map.polygons.sorted(by: { areaPriority($0.kind) < areaPriority($1.kind) }) {
            let role: Role
            switch polygon.kind {
            case .water: role = .waterTexture
            case .park: role = .parkTexture
            case .land, .building, .road, .primaryRoad: role = .landTexture
            }
            let bounds = TextureWork.bounds(polygon.rings, viewport: viewport)
            for row in bounds.rows {
                let y = (Double(row) + 0.5) / 4
                var crossings: [Double] = []
                for ring in polygon.rings {
                    for (a, b) in zip(ring, ring.dropFirst()) where (a.y > y) != (b.y > y) {
                        let x = a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x)
                        if x.isFinite { crossings.append(min(max(a.x, b.x), max(min(a.x, b.x), x))) }
                    }
                }
                crossings.sort()
                for index in stride(from: 0, to: max(0, crossings.count - 1), by: 2) {
                    let columns = TextureWork.sampleRange(crossings[index], crossings[index + 1], scale: 2, limit: width)
                    for column in columns { owners[row * width + column] = role }
                }
            }
        }
        return owners
    }

    private static func areaPriority(_ kind: MapFeature.Kind) -> Int {
        switch kind {
        case .land: 0
        case .park: 1
        case .water: 2
        case .building: 3
        case .road: 4
        case .primaryRoad: 5
        }
    }

    /// Reuses the existing work limits at the finer sampling grid. Thin polygons
    /// between cell centres are counted; multiplying the old fill count is unsafe.
    private struct TextureWork {
        let edgeVisits: Int
        let sortWeight: Int
        let candidates: Int

        init(map: PreparedMap, viewport: MapViewport, enabled: Bool) throws {
            var edges = 0, sorts = 0, writes = 0
            if enabled {
                for polygon in map.polygons {
                    let bounds = Self.bounds(polygon.rings, viewport: viewport)
                    let count = polygon.rings.reduce(0) { $0 + $1.count - 1 }
                    var remainder = max(0, count - 1), levels = 0
                    while remainder > 0 { levels += 1; remainder /= 2 }
                    try Self.add(bounds.rows.count * count, to: &edges, limit: MapDrawingWork.edgeVisitLimit)
                    try Self.add(bounds.rows.count * count * levels, to: &sorts, limit: MapDrawingWork.crossingSortWeightLimit)
                    try Self.add(bounds.rows.count * bounds.columns.count, to: &writes, limit: MapDrawingWork.fillWriteLimit)
                }
            }
            edgeVisits = edges
            sortWeight = sorts
            candidates = writes
        }

        static func bounds(_ rings: [[PreparedMap.Point]], viewport: MapViewport) -> (columns: Range<Int>, rows: Range<Int>) {
            let points = rings.joined()
            return (sampleRange(points.map(\.x).min()!, points.map(\.x).max()!, scale: 2, limit: viewport.columns * 2),
                    sampleRange(points.map(\.y).min()!, points.map(\.y).max()!, scale: 4, limit: viewport.rows * 4))
        }

        static func sampleRange(_ minimum: Double, _ maximum: Double, scale: Double, limit: Int) -> Range<Int> {
            let start = Int(ceil(min(Double(limit), max(0, minimum * scale - 0.5))))
            let end = Int(ceil(min(Double(limit), max(0, maximum * scale - 0.5))))
            return start..<max(start, end)
        }

        private static func add(_ amount: Int, to value: inout Int, limit: Int) throws {
            guard amount <= limit - value else { throw MapValidationError.drawingBudgetExceeded }
            value += amount
        }
    }
}

extension BrailleMapDrawing: Equatable {}
extension BrailleMapDrawing: Sendable {}
extension BrailleMapDrawing.Treatment: CaseIterable {}
extension BrailleMapDrawing.Role: CaseIterable {}
extension BrailleMapDrawing.Cell: Equatable {}
extension BrailleMapDrawing.Cell: Sendable {}
extension BrailleMapDrawing.Statistics: Equatable {}
extension BrailleMapDrawing.Statistics: Sendable {}
extension BrailleMapDrawing.Statistics: Encodable {}

extension BrailleMapDrawing: CanvasDrawing {
    func draw(into context: inout CanvasContext) {
        for cell in cells {
            for y in 0..<4 {
                for x in 0..<2 where cell.dots.contains(x: x, y: y) {
                    // Explicit foreground for every emitted dot; no polygon backgrounds.
                    context.setPixel(at: Point(x: Double(cell.column) + (Double(x) + 0.5) / 2,
                                               y: Double(cell.row) + (Double(y) + 0.5) / 4),
                                     foreground: cell.role.color)
                }
            }
        }
    }
}
