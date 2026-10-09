import Foundation

/// Checked XYZ address for this offline Web Mercator tile proof.
struct MapTileCoordinate {
    let zoom: Int
    let x: Int
    let y: Int

    init(zoom: Int, x: Int, y: Int) throws {
        guard (0...22).contains(zoom), (0..<(1 << zoom)).contains(x),
              (0..<(1 << zoom)).contains(y)
        else { throw ValidationError.invalidAddress }
        self.zoom = zoom
        self.x = x
        self.y = y
    }

    var coverage: MapCoverage {
        get throws {
            let southwest = try coordinate(x: 0, y: 1, extent: 1)
            let northeast = try coordinate(x: 1, y: 0, extent: 1)
            return try .boundedOfflineExtract(.init(southwest: southwest, northeast: northeast))
        }
    }

    /// Buffers retain their positions. A longitude beyond the world seam wraps;
    /// tile coverage itself always uses the unbuffered bounds.
    func coordinate(x localX: Int64, y localY: Int64, extent: Int) throws -> MapCoordinate {
        guard (1...65_536).contains(extent) else { throw ValidationError.invalidAddress }
        let side = Double(1 << zoom)
        let horizontal = (Double(x) + Double(localX) / Double(extent)) / side
        let vertical = (Double(y) + Double(localY) / Double(extent)) / side
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

    enum ValidationError: Error, Equatable, Sendable { case invalidAddress }
}

extension MapTileCoordinate: Hashable {}
extension MapTileCoordinate: Sendable {}
extension MapTileCoordinate: Codable {
    private enum CodingKeys: String, CodingKey { case zoom, x, y }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(zoom: values.decode(Int.self, forKey: .zoom),
                      x: values.decode(Int.self, forKey: .x), y: values.decode(Int.self, forKey: .y))
    }
}
