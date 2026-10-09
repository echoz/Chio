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

    private func coordinates(_ path: [MapboxVectorTileDecoder.Point], extent: Int) throws -> [MapCoordinate] {
        // Canonical geographic paths follow the shortest longitude edge. Reject
        // tile edges spanning half a world or more rather than silently changing
        // their tile-space meaning through longitude wrapping.
        let worldWidth = Int64(extent) * Int64(1 << tile.zoom)
        guard zip(path, path.dropFirst()).allSatisfy({ abs($0.1.x - $0.0.x) * 2 < worldWidth })
        else { throw MapboxVectorTileDecoder.ValidationError.invalidGeometry }
        return try path.map { try tile.coordinate(x: $0.x, y: $0.y, extent: extent) }
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
                    geometries = try paths.map { path in
                        .polyline(try MapPolyline(coordinates: coordinates(path, extent: layer.extent)))
                    }
                case .polygons(let parts):
                    guard kind != .road, kind != .primaryRoad else {
                        throw MapboxVectorTileDecoder.ValidationError.invalidGeometry
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
