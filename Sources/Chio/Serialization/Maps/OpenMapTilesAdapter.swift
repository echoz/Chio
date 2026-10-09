import Foundation

/// Explicit OpenMapTiles presentation subset for one supplied XYZ tile.
/// No tile stitching, label-layer joining, repair or acquisition happens here.
public struct OpenMapTilesAdapter {
    /// Invalid wire data, unsupported schema details and bounded decoder failures.
    public enum ValidationError {
        case malformedWire, unsupportedVersion, invalidLayer, invalidTags, invalidValue
        case invalidGeometry, budgetExceeded
    }
    public let tile: MapTileCoordinate
    public let metadata: MapSourceMetadata

    public init(tile: MapTileCoordinate, metadata: MapSourceMetadata) {
        self.tile = tile
        self.metadata = metadata
    }

    private func horizontalBounds(_ path: [MapboxVectorTileDecoder.Point]) -> (minimum: Int64, maximum: Int64) {
        // The wire decoder establishes a nonempty, bounded path first.
        var minimum = path[0].x, maximum = path[0].x
        for point in path.dropFirst() {
            minimum = min(minimum, point.x)
            maximum = max(maximum, point.x)
        }
        return (minimum, maximum)
    }

    private func normalizedVertexCount(_ path: [MapboxVectorTileDecoder.Point], extent: Int) throws -> Int {
        let worldWidth = Int64(extent) * Int64(1 << tile.zoom)
        let bounds = horizontalBounds(path)
        // A whole-world or wider raw path loses its distinct buffered longitude
        // branches in the canonical model. Do not repair or collapse those copies.
        guard bounds.maximum - bounds.minimum < worldWidth else { throw ValidationError.invalidGeometry }
        var count = 1
        for (start, end) in zip(path, path.dropFirst()) {
            let pieces = Int(abs(end.x - start.x) * 2 / worldWidth) + 1
            guard count <= MapLimits.pathVertices - pieces else { throw ValidationError.budgetExceeded }
            count += pieces
        }
        return count
    }

    private func normalizedPolygonVertexCount(_ rings: [[MapboxVectorTileDecoder.Point]], extent: Int) throws -> Int {
        let worldWidth = Int64(extent) * Int64(1 << tile.zoom)
        let exterior = horizontalBounds(rings[0])
        var vertices = 0
        for (index, ring) in rings.enumerated() {
            let count = try normalizedVertexCount(ring, extent: extent)
            guard vertices <= MapLimits.pathVertices - count else { throw ValidationError.budgetExceeded }
            vertices += count
            if index > 0 {
                let hole = horizontalBounds(ring)
                // Twice the raw midpoint distance must be strictly less than a
                // world: nearest-world alignment then uniquely recovers the source
                // branch. This is a branch invariant, not a topology repair.
                let midpointDistance = abs((hole.minimum + hole.maximum) - (exterior.minimum + exterior.maximum))
                guard midpointDistance < worldWidth else { throw ValidationError.invalidGeometry }
            }
        }
        return vertices
    }

    private func coordinates(_ path: [MapboxVectorTileDecoder.Point], extent: Int) throws -> [MapCoordinate] {
        let count = try normalizedVertexCount(path, extent: extent)
        let worldWidth = Int64(extent) * Int64(1 << tile.zoom)
        var coordinates: [MapCoordinate] = []
        coordinates.reserveCapacity(count)
        coordinates.append(try tile.coordinate(x: path[0].x, y: path[0].y, extent: extent))
        for (start, end) in zip(path, path.dropFirst()) {
            let pieces = Int(abs(end.x - start.x) * 2 / worldWidth) + 1
            for piece in 1..<pieces {
                let fraction = Double(piece) / Double(pieces)
                coordinates.append(try tile.coordinate(
                    interpolatedX: Double(start.x) + Double(end.x - start.x) * fraction,
                    interpolatedY: Double(start.y) + Double(end.y - start.y) * fraction, extent: extent))
            }
            // Preserve the original conversion exactly for every supplied vertex.
            coordinates.append(try tile.coordinate(x: end.x, y: end.y, extent: extent))
        }
        return coordinates
    }

    private func kind(layer: String, feature: MapboxVectorTileDecoder.Feature) -> MapFeature.Kind? {
        let sourceClass = feature.properties["class"]?.string ?? ""
        switch layer {
        case "water": return .water
        case "building": return .building
        // OpenMapTiles also places park name/rank POINT labels in this layer.
        // They are outside our area subset, not malformed polygon geometry.
        case "park": return feature.type == 1 ? nil : .park
        case "landuse":
            return ["park", "recreation_ground", "village_green", "garden"].contains(sourceClass) ? .park : nil
        case "transportation":
            if ["motorway", "trunk", "primary", "motorway_link", "trunk_link", "primary_link"].contains(sourceClass) {
                return .primaryRoad
            }
            return ["secondary", "tertiary", "minor", "secondary_link", "tertiary_link"].contains(sourceClass) ? .road : nil
        default: return nil
        }
    }
}

extension OpenMapTilesAdapter: MapSourceAdapter {
    public func adapt(_ input: Data) throws -> MapSource {
        try MapSource(dataset: dataset(input, admits: { _ in true }), metadata: metadata, coverage: tile.coverage)
    }

    /// Acquisition retains complete validated parts that may intersect the requested
    /// region. Its caller must describe that region, not the whole tile, as coverage.
    func adapt(_ input: Data, intersecting request: MapTileRequest) throws -> MapDataset {
        try dataset(input, admits: { try MapPreparation.mayIntersect($0, request: request) })
    }

    private func dataset(_ input: Data, admits: (MapGeometry) throws -> Bool) throws -> MapDataset {
        let layers = try MapboxVectorTileDecoder.decode(input)
        var features: [MapFeature] = []
        var vertices = 0
        for layer in layers {
            for (ordinal, feature) in layer.features.enumerated() {
                guard let kind = kind(layer: layer.name, feature: feature) else { continue }
                let name = feature.properties["name"]?.string ?? ""
                // Ordinal distinguishes missing/repeated source IDs. These identities
                // belong to this tile snapshot, not to OSM or another provider.
                let sourceID = feature.id.map(String.init) ?? "absent"
                let prefix = "mvt/\(tile.zoom)/\(tile.x)/\(tile.y)/\(layer.name)/\(ordinal)/\(sourceID)"
                let geometry = try MapboxVectorTileDecoder.geometry(feature, extent: layer.extent)
                let geometries: [MapGeometry]
                switch geometry {
                case .lines(let paths):
                    guard kind == .road || kind == .primaryRoad else {
                        throw MapboxVectorTileDecoder.ValidationError.invalidGeometry
                    }
                    var normalizedVertices = 0
                    for path in paths {
                        normalizedVertices += try normalizedVertexCount(path, extent: layer.extent)
                        guard normalizedVertices <= MapLimits.sourceVertices else { throw ValidationError.budgetExceeded }
                    }
                    geometries = try paths.map { path in
                        .polyline(try MapPolyline(coordinates: coordinates(path, extent: layer.extent)))
                    }
                case .polygons(let parts):
                    guard kind != .road, kind != .primaryRoad else {
                        throw MapboxVectorTileDecoder.ValidationError.invalidGeometry
                    }
                    var normalizedVertices = 0
                    for rings in parts {
                        normalizedVertices += try normalizedPolygonVertexCount(rings, extent: layer.extent)
                        guard normalizedVertices <= MapLimits.sourceVertices else { throw ValidationError.budgetExceeded }
                    }
                    geometries = try parts.map { rings in
                        .polygon(try MapPolygon(rings: rings.map { ring in
                            try MapRing(coordinates: coordinates(ring, extent: layer.extent))
                        }))
                    }
                }
                for (part, geometry) in geometries.enumerated() {
                    // Validate names/identities as well as geometry even offscreen.
                    let candidate = try MapFeature(id: "\(prefix)/\(part)", kind: kind, name: name, geometry: geometry)
                    guard try admits(geometry) else { continue }
                    vertices += geometry.vertexCount
                    guard features.count < MapLimits.features, vertices <= MapLimits.sourceVertices
                    else { throw MapValidationError.budgetExceeded }
                    features.append(candidate)
                }
            }
        }
        return try MapDataset(features: features)
    }
}

extension OpenMapTilesAdapter: Sendable {}
extension OpenMapTilesAdapter.ValidationError: Error {}
extension OpenMapTilesAdapter.ValidationError: Equatable {}
extension OpenMapTilesAdapter.ValidationError: Sendable {}
