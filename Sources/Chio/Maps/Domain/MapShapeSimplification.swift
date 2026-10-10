import Foundation

/// Conservative per-polygon experiment, not a topology-preserving GIS simplifier.
/// Different features are independent: shared boundaries are not coordinated.
enum MapShapeSimplification {
    static let operationLimit = 3_000_000
    private static let polygonOperationLimit = 1_000_000

    /// Explicit cuts, ordinary dateline crossings and clamped polar rings remain exact.
    /// Merely touching the seam is safe: every projected extrema vertex is pinned.
    /// Simplifying these requires geographic seam semantics outside this local spike.
    static func hasGeographicCut(_ polygon: MapPolygon) -> Bool {
        polygon.rings.contains { ring in
            ring.coordinates.contains {
                abs($0.latitude) >= MapLimits.mercatorLatitude
            } || zip(ring.coordinates, ring.coordinates.dropFirst()).contains {
                abs($0.0.longitude - $0.1.longitude) > 180
            }
        }
    }

    /// All-or-nothing: an unproved candidate, cancellation or exhausted budget returns exact input.
    /// Each ring retains extrema, winding and 85–115% of its original area. This
    /// prevents tiny/narrow water rings disappearing; it does not guarantee every
    /// local channel width or protect relationships with another feature's coast.
    static func simplify(_ rings: [[PreparedMap.Point]], tolerance: Double,
                         cellAspectRatio: Double, operationBudget: inout Int,
                         isCancelled: @escaping @Sendable () -> Bool = { false }) -> [[PreparedMap.Point]] {
        guard tolerance.isFinite, tolerance > 0, cellAspectRatio.isFinite,
              cellAspectRatio > 0, operationBudget > 0, !rings.isEmpty else { return rings }
        var remaining = Budget(remaining: min(operationBudget, polygonOperationLimit), isCancelled: isCancelled)
        let initial = remaining.remaining
        defer { operationBudget -= initial - remaining.remaining }
        do {
            try remaining.checkCancellation()
            let candidate = try rings.map {
                try remaining.checkCancellation()
                return try reduce($0, tolerance: tolerance, aspect: cellAspectRatio, budget: &remaining)
            }
            try remaining.checkCancellation()
            guard candidate != rings else { return rings }
            for (original, reduced) in zip(rings, candidate) {
                try remaining.checkCancellation()
                guard isValidRing(original), isValidRing(reduced) else { return rings }
                let before = signedArea(original), after = signedArea(reduced)
                guard before * after > 0, abs(after / before - 1) <= 0.15 else { return rings }
            }
            // Source values only promise closure/area, so do not silently repair
            // self crossings, overlapping holes or holes outside their exterior.
            guard try hasValidTopology(rings, budget: &remaining),
                  try hasValidTopology(candidate, budget: &remaining) else { return rings }
            try remaining.checkCancellation()
            return candidate
        } catch {
            return rings
        }
    }

    private static func reduce(_ ring: [PreparedMap.Point], tolerance: Double,
                               aspect: Double, budget: inout Budget) throws -> [PreparedMap.Point] {
        guard isValidRing(ring), ring.count > 4 else { return ring }
        let count = ring.count - 1
        let origin = ring[0]
        let physical = try ring.enumerated().map { index, point in
            if index.isMultiple(of: 256) { try budget.checkCancellation() }
            return PreparedMap.Point(x: point.x - origin.x, y: (point.y - origin.y) * aspect)
        }
        var anchors: Set<Int> = [0, count]
        var minX = 0, maxX = 0, minY = 0, maxY = 0
        for index in 1..<count {
            try spend(&budget)
            if physical[index].x < physical[minX].x { minX = index }
            if physical[index].x > physical[maxX].x { maxX = index }
            if physical[index].y < physical[minY].y { minY = index }
            if physical[index].y > physical[maxY].y { maxY = index }
        }
        // Keep all extrema, not only one representative. A seam-touching polygon
        // can have multiple vertices along its longitude cut; every one stays put.
        for index in 0..<count {
            try spend(&budget)
            let point = physical[index]
            if point.x == physical[minX].x || point.x == physical[maxX].x
                || point.y == physical[minY].y || point.y == physical[maxY].y {
                anchors.insert(index)
            }
        }
        let ordered = anchors.sorted()
        var retained = anchors
        var pending = Array(zip(ordered, ordered.dropFirst()))
        while let (start, end) = pending.popLast() {
            try budget.checkCancellation()
            guard end > start + 1 else { continue }
            var farthest = start, distance = tolerance * tolerance
            for index in (start + 1)..<end {
                try spend(&budget)
                let squared = squaredDistance(physical[index], to: physical[start], physical[end])
                if squared > distance { distance = squared; farthest = index }
            }
            if farthest != start {
                retained.insert(farthest)
                pending.append((start, farthest))
                pending.append((farthest, end))
            }
        }
        return retained.sorted().map { ring[$0] }
    }

    private static func squaredDistance(_ point: PreparedMap.Point, to a: PreparedMap.Point,
                                        _ b: PreparedMap.Point) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = dx * dx + dy * dy
        let fraction = length == 0 ? 0 : min(1, max(0, ((point.x - a.x) * dx + (point.y - a.y) * dy) / length))
        let x = point.x - a.x - fraction * dx, y = point.y - a.y - fraction * dy
        return x * x + y * y
    }

    private static func isValidRing(_ ring: [PreparedMap.Point]) -> Bool {
        ring.count >= 4 && ring.first == ring.last
            && ring.allSatisfy { $0.x.isFinite && $0.y.isFinite }
            && Set(ring.dropLast()).count >= 3 && signedArea(ring).isFinite && signedArea(ring) != 0
    }

    private static func signedArea(_ ring: [PreparedMap.Point]) -> Double {
        guard let origin = ring.first else { return 0 }
        // Translation-relative area avoids cancellation during distant camera pans.
        return zip(ring, ring.dropFirst()).reduce(0) {
            $0 + ($1.0.x - origin.x) * ($1.1.y - origin.y)
                - ($1.1.x - origin.x) * ($1.0.y - origin.y)
        } / 2
    }

    private static func hasValidTopology(_ rings: [[PreparedMap.Point]], budget: inout Budget) throws -> Bool {
        for ring in rings {
            try budget.checkCancellation()
            let edges = Array(zip(ring, ring.dropFirst()))
            for i in edges.indices {
                guard edges[i].0 != edges[i].1 else { return false }
                for j in (i + 1)..<edges.count {
                    try spend(&budget)
                    if j == i + 1 || (i == 0 && j == edges.count - 1) {
                        // Adjacent edges may meet, but may not reverse and overlap.
                        let shared = j == i + 1 ? edges[i].1 : edges[i].0
                        let a = j == i + 1 ? edges[i].0 : edges[i].1
                        let b = j == i + 1 ? edges[j].1 : edges[j].0
                        if orientation(a, shared, b) == 0,
                           (a.x - shared.x) * (b.x - shared.x) + (a.y - shared.y) * (b.y - shared.y) > 0 {
                            return false
                        }
                        continue
                    }
                    if intersects(edges[i].0, edges[i].1, edges[j].0, edges[j].1) { return false }
                }
            }
        }
        for i in rings.indices {
            for j in (i + 1)..<rings.count {
                for (a, b) in zip(rings[i], rings[i].dropFirst()) {
                    for (c, d) in zip(rings[j], rings[j].dropFirst()) {
                        try spend(&budget)
                        if intersects(a, b, c, d) { return false }
                    }
                }
                try spend(&budget, amount: rings[i].count + rings[j].count)
                if i == 0 {
                    guard contains(rings[j][0], ring: rings[0]) else { return false }
                } else if contains(rings[j][0], ring: rings[i]) || contains(rings[i][0], ring: rings[j]) {
                    return false // Overlapping/nested holes are not repaired.
                }
            }
        }
        return true
    }

    private static func orientation(_ a: PreparedMap.Point, _ b: PreparedMap.Point,
                                    _ c: PreparedMap.Point) -> Double {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }

    private static func intersects(_ a: PreparedMap.Point, _ b: PreparedMap.Point,
                                   _ c: PreparedMap.Point, _ d: PreparedMap.Point) -> Bool {
        // Treat touching or numerically ambiguous boundaries as unsafe too.
        let epsilon = 1e-9
        guard max(a.x, b.x) + epsilon >= min(c.x, d.x), max(c.x, d.x) + epsilon >= min(a.x, b.x),
              max(a.y, b.y) + epsilon >= min(c.y, d.y), max(c.y, d.y) + epsilon >= min(a.y, b.y) else { return false }
        let abC = orientation(a, b, c), abD = orientation(a, b, d)
        let cdA = orientation(c, d, a), cdB = orientation(c, d, b)
        func straddles(_ x: Double, _ y: Double) -> Bool {
            (x <= epsilon && y >= -epsilon) || (y <= epsilon && x >= -epsilon)
        }
        return straddles(abC, abD) && straddles(cdA, cdB)
    }

    private static func contains(_ point: PreparedMap.Point, ring: [PreparedMap.Point]) -> Bool {
        var isInside = false
        for (a, b) in zip(ring, ring.dropFirst()) where (a.y > point.y) != (b.y > point.y) {
            if point.x < a.x + (point.y - a.y) * (b.x - a.x) / (b.y - a.y) { isInside.toggle() }
        }
        return isInside
    }

    private static func spend(_ budget: inout Budget, amount: Int = 1) throws {
        if budget.remaining.isMultiple(of: 256) { try budget.checkCancellation() }
        guard budget.remaining >= amount else { budget.remaining = 0; throw Exhausted.budget }
        budget.remaining -= amount
    }

    /// Cancellation observations do not consume the existing geometry allowance.
    private struct Budget {
        var remaining: Int
        let isCancelled: @Sendable () -> Bool

        func checkCancellation() throws {
            if isCancelled() { throw CancellationError() }
        }
    }

    private enum Exhausted: Error { case budget }
}
