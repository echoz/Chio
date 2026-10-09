import Foundation

public struct MapPolyline {
    public let coordinates: [MapCoordinate]

    public init(coordinates: [MapCoordinate]) throws {
        guard coordinates.count <= MapLimits.pathVertices else { throw MapValidationError.budgetExceeded }
        guard coordinates.count >= 2, Set(coordinates).count >= 2 else { throw MapValidationError.invalidPath }
        self.coordinates = coordinates
    }
}

extension MapPolyline: Hashable {}
extension MapPolyline: Sendable {}
extension MapPolyline: Codable {
    private enum CodingKeys: String, CodingKey { case coordinates }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        var source = try values.nestedUnkeyedContainer(forKey: .coordinates)
        var coordinates: [MapCoordinate] = []
        while !source.isAtEnd {
            guard coordinates.count < MapLimits.pathVertices else { throw MapValidationError.budgetExceeded }
            coordinates.append(try source.decode(MapCoordinate.self))
        }
        try self.init(coordinates: coordinates)
    }
}
