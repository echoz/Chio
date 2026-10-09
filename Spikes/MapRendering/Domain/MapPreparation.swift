import Foundation

/// Pure bounded preparation; native SwiftTUI still owns all cell rasterization.
enum MapPreparation {
    static func prepare(dataset: MapDataset, camera: MapCamera, viewport: MapViewport) throws -> PreparedMap {
        var lines: [PreparedMap.Line] = []
        var polygons: [PreparedMap.Polygon] = []
        var labels: [PreparedMap.Label] = []
        var visibleIDs: Set<String> = []
        var preparedVertices = 0
        let wrapWidth = 360 * Double(viewport.columns) / camera.longitudeSpan
        let ordered = dataset.features.enumerated().sorted {
            if $0.element.kind.priority != $1.element.kind.priority {
                return $0.element.kind.priority < $1.element.kind.priority
            }
            return $0.offset < $1.offset
        }.map(\.element)

        for feature in ordered {
            var anchor: PreparedMap.Point?
            switch feature.geometry {
            case .polyline(let line):
                let projected = project(line.coordinates, camera: camera, viewport: viewport)
                for shift in [-1.0, 0, 1] {
                    let points = shifted(projected, by: shift * wrapWidth)
                    for path in clipped(points, viewport: viewport) {
                        let simplified = simplify(path)
                        guard simplified.count >= 2 else { continue }
                        preparedVertices += simplified.count
                        guard preparedVertices <= MapLimits.preparedVertices else { throw MapValidationError.budgetExceeded }
                        lines.append(.init(featureID: feature.id, kind: feature.kind, points: simplified))
                        let candidate = midpoint(of: path)
                        if distanceToCenter(candidate, viewport: viewport) < (anchor.map({ distanceToCenter($0, viewport: viewport) }) ?? .infinity) {
                            anchor = candidate
                        }
                    }
                }
            case .polygon(let polygon):
                let outer = project(polygon.rings[0].coordinates, camera: camera, viewport: viewport)
                // Holes use the exterior's longitude branch, rather than wrapping independently.
                let referenceX = outer.reduce(0) { $0 + $1.x } / Double(outer.count)
                let referenceLongitude = camera.center.longitude
                    + (referenceX - Double(viewport.columns) / 2) * camera.longitudeSpan / Double(viewport.columns)
                let rings = [outer] + polygon.rings.dropFirst().map {
                    project($0.coordinates, camera: camera, viewport: viewport, referenceLongitude: referenceLongitude)
                }
                for shift in [-1.0, 0, 1] {
                    let shiftedRings = rings.map { shifted($0, by: shift * wrapWidth) }
                    guard intersects(shiftedRings[0], viewport: viewport) else { continue }
                    // Retain every ring and vertex. Filling only viewport scanlines bounds work
                    // without introducing clipped border edges or destroying hole topology.
                    preparedVertices += shiftedRings.reduce(0) { $0 + $1.count }
                    guard preparedVertices <= MapLimits.preparedVertices else { throw MapValidationError.budgetExceeded }
                    polygons.append(.init(featureID: feature.id, kind: feature.kind, rings: shiftedRings))
                    for ring in shiftedRings {
                        for path in clipped(ring, viewport: viewport) {
                            let outline = simplify(path)
                            guard outline.count >= 2 else { continue }
                            preparedVertices += outline.count
                            guard preparedVertices <= MapLimits.preparedVertices else { throw MapValidationError.budgetExceeded }
                            lines.append(.init(featureID: feature.id, kind: feature.kind, points: outline))
                        }
                    }
                    if let candidate = polygonAnchor(shiftedRings, viewport: viewport),
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
        return PreparedMap(lines: lines, polygons: polygons, labels: labels,
                           statistics: .init(sourceVertices: dataset.vertexCount,
                                             preparedVertices: preparedVertices,
                                             visibleFeatures: visibleIDs.count))
    }

    private static func project(_ coordinates: [MapCoordinate], camera: MapCamera,
                                viewport: MapViewport, referenceLongitude: Double? = nil) -> [PreparedMap.Point] {
        let isClosed = coordinates.first == coordinates.last
        // An explicit -180...180 edge records the source's full-world cut. Shortest
        // unwrapping would collapse a valid polar strip even when closure still agrees.
        if isClosed, zip(coordinates, coordinates.dropFirst()).contains(where: {
            abs($0.0.longitude - $0.1.longitude) == 360
        }) {
            return coordinates.map {
                viewport.point(longitude: $0.longitude, mercatorY: MapViewport.mercatorY($0.latitude), camera: camera)
            }
        }
        var previous = referenceLongitude ?? camera.center.longitude
        var points: [PreparedMap.Point] = []
        for coordinate in coordinates {
            let longitude = MapViewport.unwrap(coordinate.longitude, near: previous)
            points.append(viewport.point(longitude: longitude, mercatorY: MapViewport.mercatorY(coordinate.latitude), camera: camera))
            previous = longitude
        }
        // A closed ring winding once around the world (a polar cap) cannot close on
        // one shortest-edge longitude branch. Keep the source's explicit dateline cut.
        if isClosed, let first = points.first, let last = points.last,
           abs(first.x - last.x) > 1e-6 {
            return coordinates.map {
                viewport.point(longitude: $0.longitude, mercatorY: MapViewport.mercatorY($0.latitude), camera: camera)
            }
        }
        return points
    }

    private static func shifted(_ points: [PreparedMap.Point], by x: Double) -> [PreparedMap.Point] {
        points.map { .init(x: $0.x + x, y: $0.y) }
    }

    private static func intersects(_ ring: [PreparedMap.Point], viewport: MapViewport) -> Bool {
        guard let first = ring.first else { return false }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in ring.dropFirst() {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return maxX >= 0 && minX <= Double(viewport.columns) && maxY >= 0 && minY <= Double(viewport.rows)
    }

    private static func clipped(_ points: [PreparedMap.Point], viewport: MapViewport) -> [[PreparedMap.Point]] {
        var paths: [[PreparedMap.Point]] = []
        var path: [PreparedMap.Point] = []
        for (a, b) in zip(points, points.dropFirst()) {
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
    private static func simplify(_ points: [PreparedMap.Point]) -> [PreparedMap.Point] {
        guard points.count > 2 else { return points }
        var reduced = [points[0]]
        for point in points.dropFirst().dropLast() {
            let previous = reduced[reduced.count - 1]
            if hypot(point.x - previous.x, point.y - previous.y) >= 0.25 { reduced.append(point) }
        }
        if reduced.last != points.last { reduced.append(points[points.count - 1]) }
        if reduced.count == 1, let farthest = points.dropFirst().dropLast().max(by: {
            hypot($0.x - points[0].x, $0.y - points[0].y) < hypot($1.x - points[0].x, $1.y - points[0].y)
        }), farthest != points[0] {
            // Preserve a sub-cell closed line as a tiny loop rather than one sample.
            reduced = [points[0], farthest, points[points.count - 1]]
        }
        return reduced
    }

    /// Use the visible path's arclength, so two-point viewport crossings label in
    /// their interior rather than at a boundary rejected by native Text placement.
    private static func midpoint(of points: [PreparedMap.Point]) -> PreparedMap.Point {
        let total = zip(points, points.dropFirst()).reduce(0.0) {
            $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y)
        }
        var remaining = total / 2
        for (a, b) in zip(points, points.dropFirst()) {
            let length = hypot(b.x - a.x, b.y - a.y)
            if length > 0, remaining <= length {
                let fraction = remaining / length
                return .init(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
            }
            remaining -= length
        }
        return points[points.count - 1]
    }

    private static func polygonAnchor(_ rings: [[PreparedMap.Point]], viewport: MapViewport) -> PreparedMap.Point? {
        let outer = rings[0]
        // The candidate must be inside the even-odd area; no label is put in a hole.
        let candidate = PreparedMap.Point(x: outer.dropLast().reduce(0) { $0 + $1.x } / Double(outer.count - 1),
                                          y: outer.dropLast().reduce(0) { $0 + $1.y } / Double(outer.count - 1))
        guard candidate.x >= 0, candidate.x < Double(viewport.columns),
              candidate.y >= 0, candidate.y < Double(viewport.rows),
              contains(candidate, rings: rings) else { return nil }
        return candidate
    }

    private static func contains(_ point: PreparedMap.Point, rings: [[PreparedMap.Point]]) -> Bool {
        var inside = false
        for ring in rings {
            for (a, b) in zip(ring, ring.dropFirst()) where (a.y > point.y) != (b.y > point.y) {
                let x = a.x + (point.y - a.y) * (b.x - a.x) / (b.y - a.y)
                if point.x < x { inside.toggle() }
            }
        }
        return inside
    }

    private static func distanceToCenter(_ point: PreparedMap.Point, viewport: MapViewport) -> Double {
        hypot(point.x - Double(viewport.columns) / 2, point.y - Double(viewport.rows) / 2)
    }
}
