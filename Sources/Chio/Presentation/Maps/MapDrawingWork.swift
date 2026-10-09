import Foundation

/// Conservative drawing admission counts, independent of colors and native rasterization.
/// Sort weight models input complexity; it is not an exact Swift sort comparison count.
struct MapDrawingWork {
    let geometryElements: Int
    let edgeVisits: Int
    let crossingSortWeight: Int
    let fillWrites: Int
    let strokeSamples: Int

    static let edgeVisitLimit = 2_000_000
    static let crossingSortWeightLimit = 16_000_000
    static let fillWriteLimit = 250_000
    static let strokeSampleLimit = 250_000

    init(map: PreparedMap, viewport: MapViewport, fills: Bool, routes: [PreparedMap.Line] = []) throws {
        let lines = map.lines + routes
        var elements = 0
        // Charge metadata as well as vertices: empty collections cannot evade preflight.
        try Self.add(lines.count, to: &elements, limit: MapLimits.preparedVertices)
        try Self.add(map.polygons.count, to: &elements, limit: MapLimits.preparedVertices)
        for line in lines {
            try Self.add(line.points.count, to: &elements, limit: MapLimits.preparedVertices)
            guard line.points.count >= 2,
                  line.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite })
            else { throw MapValidationError.invalidPath }
        }
        for polygon in map.polygons {
            try Self.add(polygon.rings.count, to: &elements, limit: MapLimits.preparedVertices)
            guard !polygon.rings.isEmpty else { throw MapValidationError.invalidRing }
            for ring in polygon.rings {
                try Self.add(ring.count, to: &elements, limit: MapLimits.preparedVertices)
                guard ring.count >= 4, ring.first == ring.last,
                      ring.allSatisfy({ $0.x.isFinite && $0.y.isFinite })
                else { throw MapValidationError.invalidRing }
            }
        }

        var edges = 0, sorts = 0, writes = 0, samples = 0
        if fills {
            for polygon in map.polygons {
                let bounds = Self.fillBounds(polygon.rings, viewport: viewport)
                let edgeCount = polygon.rings.reduce(0) { $0 + $1.count - 1 }
                try Self.addProduct(bounds.rows.count, edgeCount, to: &edges, limit: Self.edgeVisitLimit)
                let sortWeight = edgeCount * Self.sortLevels(edgeCount)
                try Self.addProduct(bounds.rows.count, sortWeight, to: &sorts, limit: Self.crossingSortWeightLimit)
                // Paired even-odd intervals are disjoint; holes cannot increase this bound.
                try Self.addProduct(bounds.rows.count, bounds.columns.count, to: &writes, limit: Self.fillWriteLimit)
            }
        }
        for line in lines {
            for (a, b) in zip(line.points, line.points.dropFirst()) {
                let segment = StrokeSegment(a, b, viewport: viewport)
                try Self.add(segment.sampleCount, to: &samples, limit: Self.strokeSampleLimit)
            }
        }
        geometryElements = elements
        edgeVisits = edges
        crossingSortWeight = sorts
        fillWrites = writes
        strokeSamples = samples
    }

    /// Includes every ring, because the accepted source subset does not prove that
    /// holes lie within their exterior. Bounds never repair that source geometry.
    static func fillBounds(_ rings: [[PreparedMap.Point]], viewport: MapViewport) -> FillBounds {
        var minX = Double(viewport.columns), maxX = 0.0
        var minY = Double(viewport.rows), maxY = 0.0
        for ring in rings {
            for point in ring {
                minX = min(minX, point.x); maxX = max(maxX, point.x)
                minY = min(minY, point.y); maxY = max(maxY, point.y)
            }
        }
        return FillBounds(columns: centerRange(minX, maxX, limit: viewport.columns),
                          rows: centerRange(minY, maxY, limit: viewport.rows))
    }

    /// Clamp before conversion, including finite projected coordinates beyond Int's range.
    private static func centerRange(_ minimum: Double, _ maximum: Double, limit: Int) -> Range<Int> {
        let start = Int(ceil(min(Double(limit), max(0, minimum - 0.5))))
        let end = Int(ceil(min(Double(limit), max(0, maximum - 0.5))))
        return start..<max(start, end)
    }

    private static func sortLevels(_ count: Int) -> Int {
        var remaining = max(0, count - 1), levels = 0
        while remaining > 0 {
            remaining /= 2
            levels += 1
        }
        return levels
    }

    private static func add(_ amount: Int, to count: inout Int, limit: Int) throws {
        guard amount >= 0, amount <= limit - count else { throw MapValidationError.drawingBudgetExceeded }
        count += amount
    }

    private static func addProduct(_ a: Int, _ b: Int, to count: inout Int, limit: Int) throws {
        guard a >= 0, b >= 0, a == 0 || b <= (limit - count) / a
        else { throw MapValidationError.drawingBudgetExceeded }
        count += a * b
    }

    struct FillBounds {
        let columns: Range<Int>
        let rows: Range<Int>
    }

    /// Exactly the sampling convention used by the native 2×4 braille drawing.
    /// Every segment includes both endpoints, including duplicate junction samples.
    struct StrokeSegment {
        let x0: Double
        let y0: Double
        let x1: Double
        let y1: Double
        let steps: Int

        init(_ a: PreparedMap.Point, _ b: PreparedMap.Point, viewport: MapViewport) {
            x0 = min(Double(viewport.columns) - 0.001, max(0, a.x))
            y0 = min(Double(viewport.rows) - 0.001, max(0, a.y))
            x1 = min(Double(viewport.columns) - 0.001, max(0, b.x))
            y1 = min(Double(viewport.rows) - 0.001, max(0, b.y))
            steps = max(1, Int(ceil(max(abs(x1 - x0) * 2, abs(y1 - y0) * 4))))
        }

        var sampleCount: Int { steps + 1 }
    }
}

extension MapDrawingWork: Equatable {}
extension MapDrawingWork: Sendable {}
