import Foundation

/// Pure bounded preparation; native SwiftTUI still owns all cell rasterization.
enum MapPreparation {
    /// The effect owner supplies cancellation. A cancelled request throws before
    /// returning any snapshot; the default keeps synchronous callers deterministic.
    static func prepare(dataset: MapDataset, camera: MapCamera, viewport: MapViewport,
                        detail: MapDetail = .source,
                        isCancelled: @escaping @Sendable () -> Bool = { false }) throws -> PreparedMap {
        let cancellation = Cancellation(isCancelled: isCancelled)
        try cancellation.check()
        var lines: [PreparedMap.Line] = []
        var polygons: [PreparedMap.Polygon] = []
        var labels: [PreparedMap.Label] = []
        var visibleIDs: Set<String> = []
        var preparedVertices = 0
        var shapeOperations = MapShapeSimplification.operationLimit
        let wrapWidth = 360 * Double(viewport.columns) / camera.longitudeSpan
        let ordered = dataset.features.enumerated().sorted {
            if $0.element.kind.priority != $1.element.kind.priority {
                return $0.element.kind.priority < $1.element.kind.priority
            }
            return $0.offset < $1.offset
        }.map(\.element)

        for feature in ordered {
            try cancellation.check()
            guard detail.admits(feature.kind, camera: camera, viewport: viewport) else { continue }
            var anchor: PreparedMap.Point?
            switch feature.geometry {
            case .polyline(let line):
                let projected = try project(line.coordinates, camera: camera, viewport: viewport, cancellation: cancellation)
                for shift in [-1.0, 0, 1] {
                    try cancellation.check()
                    let points = try shifted(projected, by: shift * wrapWidth, cancellation: cancellation)
                    for path in try clipped(points, viewport: viewport, cancellation: cancellation) {
                        try cancellation.check()
                        let simplified = try simplify(path, cancellation: cancellation)
                        guard simplified.count >= 2 else { continue }
                        preparedVertices += simplified.count
                        guard preparedVertices <= MapLimits.preparedVertices else { throw MapValidationError.budgetExceeded }
                        lines.append(.init(featureID: feature.id, kind: feature.kind, points: simplified))
                        let candidate = try midpoint(of: path, cancellation: cancellation)
                        if distanceToCenter(candidate, viewport: viewport) < (anchor.map({ distanceToCenter($0, viewport: viewport) }) ?? .infinity) {
                            anchor = candidate
                        }
                    }
                }
            case .polygon(let polygon):
                let outer = try project(polygon.rings[0].coordinates, camera: camera, viewport: viewport, cancellation: cancellation)
                // Holes use the exterior's longitude branch, rather than wrapping independently.
                let referenceX = try outer.enumerated().reduce(0.0) {
                    try cancellation.check(index: $1.offset)
                    return $0 + $1.element.x
                } / Double(outer.count)
                let referenceLongitude = camera.center.longitude
                    + (referenceX - Double(viewport.columns) / 2) * camera.longitudeSpan / Double(viewport.columns)
                let rings = try [outer] + polygon.rings.dropFirst().map {
                    try cancellation.check()
                    return try project($0.coordinates, camera: camera, viewport: viewport,
                                       referenceLongitude: referenceLongitude, cancellation: cancellation)
                }
                // Cull and admit source geometry before spending generalization work.
                // Admission stays monotonic across levels and independent of fallback.
                let admittedShifts = try [-1.0, 0, 1].filter { shift in
                    try cancellation.check()
                    let sourceRings = try rings.map { try shifted($0, by: shift * wrapWidth, cancellation: cancellation) }
                    return try intersects(sourceRings[0], viewport: viewport, cancellation: cancellation)
                        && (detail == .source || detail.admitsArea(visibleArea(sourceRings, viewport: viewport, cancellation: cancellation),
                                                                   kind: feature.kind))
                }
                guard !admittedShifts.isEmpty else { continue }
                let preparedRings: [[PreparedMap.Point]]
                let tolerance = detail.shapeTolerance(for: feature.kind)
                if tolerance > 0, !MapShapeSimplification.hasGeographicCut(polygon) {
                    preparedRings = MapShapeSimplification.simplify(rings, tolerance: tolerance,
                                                                   cellAspectRatio: viewport.cellAspectRatio,
                                                                   operationBudget: &shapeOperations,
                                                                   isCancelled: isCancelled)
                } else {
                    preparedRings = rings
                }
                try cancellation.check()
                for shift in admittedShifts {
                    try cancellation.check()
                    let shiftedRings = try preparedRings.map { try shifted($0, by: shift * wrapWidth, cancellation: cancellation) }
                    // Generalize closed rings before clipping their matching outlines.
                    // Scanline fill keeps offscreen geometry and all accepted hole rings.
                    preparedVertices += shiftedRings.reduce(0) { $0 + $1.count }
                    guard preparedVertices <= MapLimits.preparedVertices else { throw MapValidationError.budgetExceeded }
                    polygons.append(.init(featureID: feature.id, kind: feature.kind, rings: shiftedRings))
                    for ring in shiftedRings where detail.outlines(feature.kind) {
                        try cancellation.check()
                        for path in try clipped(ring, viewport: viewport, cancellation: cancellation) {
                            try cancellation.check()
                            let outline = try simplify(path, cancellation: cancellation)
                            guard outline.count >= 2 else { continue }
                            preparedVertices += outline.count
                            guard preparedVertices <= MapLimits.preparedVertices else { throw MapValidationError.budgetExceeded }
                            lines.append(.init(featureID: feature.id, kind: feature.kind, points: outline))
                        }
                    }
                    if let candidate = try polygonAnchor(shiftedRings, viewport: viewport, cancellation: cancellation),
                       distanceToCenter(candidate, viewport: viewport) < (anchor.map({ distanceToCenter($0, viewport: viewport) }) ?? .infinity) {
                        anchor = candidate
                    }
                }
            }
            let isVisible = lines.last?.featureID == feature.id || polygons.last?.featureID == feature.id
            if isVisible { visibleIDs.insert(feature.id) }
            if !feature.name.isEmpty, let anchor {
                labels.append(.init(featureID: feature.id, kind: feature.kind, text: feature.name, position: anchor))
            }
        }
        // Candidates remain stable within each priority; native Text placement owns collision checks.
        labels.sort { $0.kind.priority > $1.kind.priority }
        try cancellation.check()
        return PreparedMap(lines: lines, polygons: polygons, labels: labels,
                           statistics: .init(sourceVertices: dataset.vertexCount,
                                             preparedVertices: preparedVertices,
                                             visibleFeatures: visibleIDs.count))
    }

    private static func project(_ coordinates: [MapCoordinate], camera: MapCamera,
                                viewport: MapViewport, referenceLongitude: Double? = nil,
                                cancellation: Cancellation) throws -> [PreparedMap.Point] {
        let isClosed = coordinates.first == coordinates.last
        // An explicit -180...180 edge records the source's full-world cut. Shortest
        // unwrapping would collapse a valid polar strip even when closure still agrees.
        if isClosed, try zip(coordinates, coordinates.dropFirst()).enumerated().contains(where: {
            try cancellation.check(index: $0.offset)
            return abs($0.element.0.longitude - $0.element.1.longitude) == 360
        }) {
            return try coordinates.enumerated().map {
                try cancellation.check(index: $0.offset)
                return viewport.point(longitude: $0.element.longitude, mercatorY: MapViewport.mercatorY($0.element.latitude), camera: camera)
            }
        }
        var previous = referenceLongitude ?? camera.center.longitude
        var points: [PreparedMap.Point] = []
        for (index, coordinate) in coordinates.enumerated() {
            try cancellation.check(index: index)
            let longitude = MapViewport.unwrap(coordinate.longitude, near: previous)
            points.append(viewport.point(longitude: longitude, mercatorY: MapViewport.mercatorY(coordinate.latitude), camera: camera))
            previous = longitude
        }
        // A closed ring winding once around the world (a polar cap) cannot close on
        // one shortest-edge longitude branch. Keep the source's explicit dateline cut.
        if isClosed, let first = points.first, let last = points.last,
           abs(first.x - last.x) > 1e-6 {
            return try coordinates.enumerated().map {
                try cancellation.check(index: $0.offset)
                return viewport.point(longitude: $0.element.longitude, mercatorY: MapViewport.mercatorY($0.element.latitude), camera: camera)
            }
        }
        return points
    }

    private static func shifted(_ points: [PreparedMap.Point], by x: Double,
                                cancellation: Cancellation) throws -> [PreparedMap.Point] {
        try points.enumerated().map {
            try cancellation.check(index: $0.offset)
            return .init(x: $0.element.x + x, y: $0.element.y)
        }
    }

    private static func intersects(_ ring: [PreparedMap.Point], viewport: MapViewport,
                                   cancellation: Cancellation) throws -> Bool {
        guard let first = ring.first else { return false }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for (index, point) in ring.dropFirst().enumerated() {
            try cancellation.check(index: index)
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return maxX >= 0 && minX <= Double(viewport.columns) && maxY >= 0 && minY <= Double(viewport.rows)
    }

    private static func clipped(_ points: [PreparedMap.Point], viewport: MapViewport,
                                cancellation: Cancellation) throws -> [[PreparedMap.Point]] {
        var paths: [[PreparedMap.Point]] = []
        var path: [PreparedMap.Point] = []
        for (index, segment) in zip(points, points.dropFirst()).enumerated() {
            try cancellation.check(index: index)
            let (a, b) = segment
            guard let (start, end) = clip(a, b, viewport: viewport), start != end else {
                if path.count >= 2 { paths.append(path) }
                path = []
                continue
            }
            if path.last == start {
                path.append(end)
            } else {
                if path.count >= 2 { paths.append(path) }
                path = [start, end]
            }
        }
        if path.count >= 2 { paths.append(path) }
        return paths
    }

    /// Clip temporary copies only to measure visible area for admission. The prepared
    /// polygons keep closed rings: admission never creates borders or changes holes.
    private static func visibleArea(_ rings: [[PreparedMap.Point]], viewport: MapViewport,
                                    cancellation: Cancellation) throws -> Double {
        func area(_ ring: [PreparedMap.Point]) throws -> Double {
            var points = Array(ring.dropLast())
            for (horizontal, boundary, greater) in [(true, 0.0, true), (true, Double(viewport.columns), false),
                                                   (false, 0.0, true), (false, Double(viewport.rows), false)] {
                try cancellation.check()
                guard !points.isEmpty else { return 0 }
                func value(_ point: PreparedMap.Point) -> Double { horizontal ? point.x : point.y }
                func inside(_ point: PreparedMap.Point) -> Bool {
                    greater ? value(point) >= boundary : value(point) <= boundary
                }
                var output: [PreparedMap.Point] = []
                var previous = points[points.count - 1]
                for (index, point) in points.enumerated() {
                    try cancellation.check(index: index)
                    if inside(previous) != inside(point) {
                        let fraction = (boundary - value(previous)) / (value(point) - value(previous))
                        output.append(.init(x: previous.x + (point.x - previous.x) * fraction,
                                            y: previous.y + (point.y - previous.y) * fraction))
                    }
                    if inside(point) { output.append(point) }
                    previous = point
                }
                points = output
            }
            guard let last = points.last else { return 0 }
            var previous = last
            var twiceArea = 0.0
            for (index, point) in points.enumerated() {
                try cancellation.check(index: index)
                twiceArea += previous.x * point.y - point.x * previous.y
                previous = point
            }
            return abs(twiceArea) / 2
        }
        return try max(0, area(rings[0]) - rings.dropFirst().reduce(0) {
            try cancellation.check()
            return try $0 + area($1)
        })
    }

    /// Liang-Barsky: native line calls receive only finite viewport-bounded endpoints.
    private static func clip(_ a: PreparedMap.Point, _ b: PreparedMap.Point,
                             viewport: MapViewport) -> (PreparedMap.Point, PreparedMap.Point)? {
        let dx = b.x - a.x, dy = b.y - a.y
        var start = 0.0, end = 1.0
        for (p, q) in [(-dx, a.x), (dx, Double(viewport.columns) - a.x),
                       (-dy, a.y), (dy, Double(viewport.rows) - a.y)] {
            if p == 0 {
                if q < 0 { return nil }
            } else {
                let fraction = q / p
                if p < 0 { start = max(start, fraction) } else { end = min(end, fraction) }
                if start > end { return nil }
            }
        }
        func point(_ fraction: Double) -> PreparedMap.Point {
            .init(x: min(Double(viewport.columns), max(0, a.x + fraction * dx)),
                  y: min(Double(viewport.rows), max(0, a.y + fraction * dy)))
        }
        return (point(start), point(end))
    }

    /// Linear work. Removed samples stay within 0.25 cell of a retained endpoint.
    /// Endpoints are always kept; polygon rings never use this line-only reduction.
    private static func simplify(_ points: [PreparedMap.Point], cancellation: Cancellation) throws -> [PreparedMap.Point] {
        guard points.count > 2 else { return points }
        var reduced = [points[0]]
        for (index, point) in points.dropFirst().dropLast().enumerated() {
            try cancellation.check(index: index)
            let previous = reduced[reduced.count - 1]
            if hypot(point.x - previous.x, point.y - previous.y) >= 0.25 { reduced.append(point) }
        }
        if reduced.last != points.last { reduced.append(points[points.count - 1]) }
        if reduced.count == 1, let farthest = try points.dropFirst().dropLast().enumerated().max(by: {
            try cancellation.check(index: $1.offset)
            return hypot($0.element.x - points[0].x, $0.element.y - points[0].y)
                < hypot($1.element.x - points[0].x, $1.element.y - points[0].y)
        })?.element, farthest != points[0] {
            // Preserve a sub-cell closed line as a tiny loop rather than one sample.
            reduced = [points[0], farthest, points[points.count - 1]]
        }
        try cancellation.check()
        return reduced
    }

    /// Use the visible path's arclength, so two-point viewport crossings label in
    /// their interior rather than at a boundary rejected by native Text placement.
    private static func midpoint(of points: [PreparedMap.Point], cancellation: Cancellation) throws -> PreparedMap.Point {
        let total = try zip(points, points.dropFirst()).enumerated().reduce(0.0) {
            try cancellation.check(index: $1.offset)
            return $0 + hypot($1.element.1.x - $1.element.0.x, $1.element.1.y - $1.element.0.y)
        }
        var remaining = total / 2
        for (index, segment) in zip(points, points.dropFirst()).enumerated() {
            try cancellation.check(index: index)
            let (a, b) = segment
            let length = hypot(b.x - a.x, b.y - a.y)
            if length > 0, remaining <= length {
                let fraction = remaining / length
                return .init(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
            }
            remaining -= length
        }
        return points[points.count - 1]
    }

    private static func polygonAnchor(_ rings: [[PreparedMap.Point]], viewport: MapViewport,
                                      cancellation: Cancellation) throws -> PreparedMap.Point? {
        let outer = rings[0]
        // The candidate must be inside the even-odd area; no label is put in a hole.
        let candidate = try PreparedMap.Point(x: outer.dropLast().enumerated().reduce(0.0) {
            try cancellation.check(index: $1.offset)
            return $0 + $1.element.x
        } / Double(outer.count - 1), y: outer.dropLast().enumerated().reduce(0.0) {
            try cancellation.check(index: $1.offset)
            return $0 + $1.element.y
        } / Double(outer.count - 1))
        guard candidate.x >= 0, candidate.x < Double(viewport.columns),
              candidate.y >= 0, candidate.y < Double(viewport.rows),
              try contains(candidate, rings: rings, cancellation: cancellation) else { return nil }
        return candidate
    }

    private static func contains(_ point: PreparedMap.Point, rings: [[PreparedMap.Point]],
                                 cancellation: Cancellation) throws -> Bool {
        var inside = false
        for ring in rings {
            try cancellation.check()
            for (index, segment) in zip(ring, ring.dropFirst()).enumerated() {
                try cancellation.check(index: index)
                let (a, b) = segment
                guard (a.y > point.y) != (b.y > point.y) else { continue }
                let x = a.x + (point.y - a.y) * (b.x - a.x) / (b.y - a.y)
                if point.x < x { inside.toggle() }
            }
        }
        return inside
    }

    private static func distanceToCenter(_ point: PreparedMap.Point, viewport: MapViewport) -> Double {
        hypot(point.x - Double(viewport.columns) / 2, point.y - Double(viewport.rows) / 2)
    }

    /// Explicit observation supplied by the effect owner; domain work never reads task state.
    private struct Cancellation {
        let isCancelled: @Sendable () -> Bool

        func check() throws {
            if isCancelled() { throw CancellationError() }
        }

        func check(index: Int) throws {
            if index.isMultiple(of: 256) { try check() }
        }
    }
}
