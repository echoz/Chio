import Foundation

/// Successfully acquired XYZ inputs for a retained drawing region. Complete
/// accepted parts may have been culled outside that region; whole tiles are not
/// therefore claimed as available geometry.
public struct MapTileCoverage {
    public let tiles: [MapTileCoordinate]
    public let region: MapTileRequest

    public init(tiles: [MapTileCoordinate], region: MapTileRequest) throws {
        guard let first = tiles.first, tiles.count <= MapTilePlan.tileLimit,
              Set(tiles).count == tiles.count, tiles.allSatisfy({ $0.zoom == first.zoom }),
              let plan = try? MapTilePlan(request: region, zoom: first.zoom),
              Set(plan.tiles).isSubset(of: Set(tiles))
        else { throw MapValidationError.invalidTileCoverage }
        self.tiles = tiles.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        self.region = region
    }

    public var zoom: Int { tiles[0].zoom }

    public func contains(_ coordinate: MapCoordinate) -> Bool {
        guard region.contains(coordinate) else { return false }
        let side = 1 << zoom
        let horizontal = (coordinate.longitude + 180) / 360 * Double(side)
        let vertical = (180 - MapViewport.mercatorY(coordinate.latitude)) / 360 * Double(side)
        let x = Int(floor(MapTilePlan.boundary(horizontal, side: side))) % side
        let y = max(0, min(side - 1, Int(floor(MapTilePlan.boundary(vertical, side: side)))))
        return tiles.contains { $0.x == x && $0.y == y }
    }

    /// Every required tile must have succeeded, and the full requested region
    /// must remain inside the region whose geometry was admitted.
    public func covers(_ request: MapTileRequest) -> Bool {
        guard region.covers(request), let plan = try? MapTilePlan(request: request, zoom: zoom) else { return false }
        return Set(plan.tiles).isSubset(of: Set(tiles))
    }
}

extension MapTileCoverage: Hashable {}
extension MapTileCoverage: Sendable {}
extension MapTileCoverage: Codable {
    private enum CodingKeys: String, CodingKey { case tiles, region }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        var input = try values.nestedUnkeyedContainer(forKey: .tiles)
        var tiles: [MapTileCoordinate] = []
        while !input.isAtEnd {
            guard tiles.count < MapTilePlan.tileLimit else { throw MapValidationError.invalidTileCoverage }
            tiles.append(try input.decode(MapTileCoordinate.self))
        }
        try self.init(tiles: tiles, region: values.decode(MapTileRequest.self, forKey: .region))
    }
}
