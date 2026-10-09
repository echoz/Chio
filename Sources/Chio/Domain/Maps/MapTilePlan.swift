import Foundation

/// A complete bounded set of XYZ addresses, never a truncated viewport footprint.
struct MapTilePlan {
    static let tileLimit = 16
    let tiles: [MapTileCoordinate]

    init(request: MapTileRequest, zoom: Int) throws {
        guard (0...22).contains(zoom) else { throw MapTileCoordinate.ValidationError.invalidAddress }
        let side = 1 << zoom
        let span = request.camera.longitudeSpan
        let center = request.camera.center
        let scale = Double(side) / 360
        let west = (center.longitude - span / 2 + 180) * scale
        let east = (center.longitude + span / 2 + 180) * scale
        let halfHeight = span * Double(request.viewport.rows) * request.viewport.cellAspectRatio
            / (2 * Double(request.viewport.columns))
        let centerY = MapViewport.mercatorY(center.latitude)
        let north = (180 - min(180, centerY + halfHeight)) * scale
        let south = (180 - max(-180, centerY - halfHeight)) * scale
        let firstX = Int(floor(Self.boundary(west, side: side)))
        let lastX = Int(ceil(Self.boundary(east, side: side))) - 1
        let firstY = max(0, min(side - 1, Int(floor(Self.boundary(north, side: side)))))
        let lastY = max(0, min(side - 1, Int(ceil(Self.boundary(south, side: side))) - 1))
        let xCount = min(side, lastX - firstX + 1)
        let yCount = lastY - firstY + 1
        guard xCount > 0, yCount > 0,
              xCount <= Self.tileLimit, yCount <= Self.tileLimit / xCount
        else { throw MapValidationError.tileLimitExceeded }
        var addresses: [MapTileCoordinate] = []
        for x in firstX..<(firstX + xCount) {
            let wrapped = ((x % side) + side) % side
            for y in firstY...lastY {
                addresses.append(try MapTileCoordinate(zoom: zoom, x: wrapped, y: y))
            }
        }
        tiles = addresses.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
    }

    /// Projection and its inverse can put an exact tile edge a few floating-point
    /// units across its boundary. Resolve only that numerical roundoff before
    /// applying half-open intervals; the allowance scales with the XYZ grid.
    static func boundary(_ value: Double, side: Int) -> Double {
        let nearest = value.rounded()
        return abs(value - nearest) <= Double(side).ulp * 8 ? nearest : value
    }

    /// A tile is targeted at about 48 terminal columns before budget fallback.
    static func desiredZoom(for request: MapTileRequest, range: ClosedRange<Int>) -> Int {
        let resolution = 360 * Double(request.viewport.columns)
            / (48 * request.camera.longitudeSpan)
        let zoom = Int(floor(log2(resolution)))
        return min(range.upperBound, max(range.lowerBound, zoom))
    }
}
