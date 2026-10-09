import Foundation

/// Closed GeoJSON linear ring. Winding is immaterial to the even-odd fill experiment.
/// This subset checks closure, distinct vertices and area, not full GIS topology.
struct MapRing {
    let coordinates: [MapCoordinate]

    init(coordinates: [MapCoordinate]) throws {
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

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(coordinates: values.decode([MapCoordinate].self, forKey: .coordinates))
    }
}
