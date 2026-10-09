import Foundation

/// Closed GeoJSON linear ring. Winding is immaterial to the even-odd map fill.
/// This subset checks closure, distinct vertices and area, not full GIS topology.
public struct MapRing {
    public let coordinates: [MapCoordinate]

    public init(coordinates: [MapCoordinate]) throws {
        guard coordinates.count <= MapLimits.pathVertices else { throw MapValidationError.budgetExceeded }
        guard coordinates.count >= 4, coordinates.first == coordinates.last,
              Set(coordinates.dropLast()).count >= 3
        else { throw MapValidationError.invalidRing }
        let twiceArea = zip(coordinates, coordinates.dropFirst()).reduce(0.0) {
            $0 + $1.0.longitude * $1.1.latitude - $1.1.longitude * $1.0.latitude
        }
        guard twiceArea != 0 else { throw MapValidationError.invalidRing }
        self.coordinates = coordinates
    }
}

extension MapRing: Hashable {}
extension MapRing: Sendable {}
extension MapRing: Codable {
    private enum CodingKeys: String, CodingKey { case coordinates }

    public init(from decoder: any Decoder) throws {
        try self.init(from: decoder, vertexLimit: MapLimits.pathVertices)
    }

    /// The enclosing polygon supplies its remaining shared vertex allowance.
    init(from decoder: any Decoder, vertexLimit: Int) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        var source = try values.nestedUnkeyedContainer(forKey: .coordinates)
        var coordinates: [MapCoordinate] = []
        while !source.isAtEnd {
            guard coordinates.count < min(vertexLimit, MapLimits.pathVertices)
            else { throw MapValidationError.budgetExceeded }
            coordinates.append(try source.decode(MapCoordinate.self))
        }
        try self.init(coordinates: coordinates)
    }
}
