import Foundation

/// Checked XYZ address for a Web Mercator tile.
public struct MapTileCoordinate {
    public let zoom: Int
    public let x: Int
    public let y: Int

    public init(zoom: Int, x: Int, y: Int) throws {
        guard (0...22).contains(zoom) else { throw ValidationError.invalidAddress }
        let hasValidX = (0..<(1 << zoom)).contains(x)
        let hasValidY = (0..<(1 << zoom)).contains(y)
        guard hasValidX, hasValidY else { throw ValidationError.invalidAddress }
        self.zoom = zoom
        self.x = x
        self.y = y
    }

    public var coverage: MapCoverage {
        get throws {
            let southwest = try coordinate(x: 0, y: 1, extent: 1)
            let northeast = try coordinate(x: 1, y: 0, extent: 1)
            return try .boundedOfflineExtract(MapCoverage.Bounds(southwest: southwest, northeast: northeast))
        }
    }

    /// Buffers retain their positions. A longitude beyond the world seam wraps;
    /// tile coverage itself always uses the unbuffered bounds.
    func coordinate(x localX: Int64, y localY: Int64, extent: Int) throws -> MapCoordinate {
        try coordinate(interpolatedX: Double(localX), interpolatedY: Double(localY), extent: extent)
    }

    /// Fractional tile-space vertices preserve the source's straight projected
    /// edges when the adapter subdivides an ambiguous longitude step.
    func coordinate(interpolatedX localX: Double, interpolatedY localY: Double,
                    extent: Int) throws -> MapCoordinate {
        let hasSupportedExtent = (1...65_536).contains(extent)
        let hasFinitePosition = localX.isFinite && localY.isFinite
        guard hasSupportedExtent, hasFinitePosition else { throw ValidationError.invalidAddress }
        let side = Double(1 << zoom)
        let horizontal = (Double(x) + localX / Double(extent)) / side
        let vertical = (Double(y) + localY / Double(extent)) / side
        let rawLongitude = horizontal * 360 - 180
        let longitude: Double
        if (-180...180).contains(rawLongitude) {
            longitude = rawLongitude
        } else {
            longitude = rawLongitude - floor((rawLongitude + 180) / 360) * 360
        }
        let latitude = atan(sinh(.pi * (1 - 2 * vertical))) * 180 / .pi
        return try MapCoordinate(latitude: latitude, longitude: longitude)
    }

    public enum ValidationError { case invalidAddress }
}

extension MapTileCoordinate: Hashable {}
extension MapTileCoordinate: Sendable {}
extension MapTileCoordinate: Codable {
    private enum CodingKeys: String, CodingKey { case zoom, x, y }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(zoom: values.decode(Int.self, forKey: .zoom),
                      x: values.decode(Int.self, forKey: .x), y: values.decode(Int.self, forKey: .y))
    }
}

extension MapTileCoordinate.ValidationError: Error {}
extension MapTileCoordinate.ValidationError: Equatable {}
extension MapTileCoordinate.ValidationError: Sendable {}
