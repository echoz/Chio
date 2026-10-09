import Foundation

struct MapPolyline {
    let coordinates: [MapCoordinate]

    init(coordinates: [MapCoordinate]) throws {
        guard coordinates.count <= MapLimits.pathVertices else { throw MapValidationError.budgetExceeded }
        guard coordinates.count >= 2, Set(coordinates).count >= 2 else { throw MapValidationError.invalidPath }
        self.coordinates = coordinates
    }
}

extension MapPolyline: Hashable {}
extension MapPolyline: Sendable {}
extension MapPolyline: Codable {
    private enum CodingKeys: String, CodingKey { case coordinates }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(coordinates: values.decode([MapCoordinate].self, forKey: .coordinates))
    }
}
