/// Geographic availability, not the bounding box of retained complete geometries.
public enum MapCoverage {
    case worldwide
    case boundedOfflineExtract(Bounds)
    case tiled(MapTileCoverage)

    public func contains(_ coordinate: MapCoordinate) -> Bool {
        switch self {
        case .worldwide: true
        case .tiled(let coverage): coverage.contains(coordinate)
        case .boundedOfflineExtract(let bounds):
            (bounds.southwest.longitude...bounds.northeast.longitude).contains(coordinate.longitude)
                && (bounds.southwest.latitude...bounds.northeast.latitude).contains(coordinate.latitude)
        }
    }

    /// A nonwrapping geographic query box. Complete source features may extend beyond it.
    public struct Bounds {
        public let southwest: MapCoordinate
        public let northeast: MapCoordinate

        public init(southwest: MapCoordinate, northeast: MapCoordinate) throws {
            let hasIncreasingLongitude = southwest.longitude < northeast.longitude
            let hasIncreasingLatitude = southwest.latitude < northeast.latitude
            guard hasIncreasingLongitude, hasIncreasingLatitude else { throw ValidationError.invalidBounds }
            self.southwest = southwest
            self.northeast = northeast
        }
    }

    public enum ValidationError {
        case invalidBounds
    }
}

extension MapCoverage: Hashable {}
extension MapCoverage: Sendable {}
extension MapCoverage: Codable {}
extension MapCoverage.Bounds: Hashable {}
extension MapCoverage.Bounds: Sendable {}
extension MapCoverage.Bounds: Codable {
    private enum CodingKeys: String, CodingKey { case southwest, northeast }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(southwest: values.decode(MapCoordinate.self, forKey: .southwest),
                      northeast: values.decode(MapCoordinate.self, forKey: .northeast))
    }
}

extension MapCoverage.ValidationError: Error {}
extension MapCoverage.ValidationError: Equatable {}
extension MapCoverage.ValidationError: Sendable {}
