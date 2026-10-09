import Foundation

/// First ring is the exterior; remaining rings are retained as holes, with no repair.
struct MapPolygon {
    let rings: [MapRing]

    init(rings: [MapRing]) throws {
        guard !rings.isEmpty else { throw MapValidationError.invalidRing }
        guard rings.count <= MapLimits.polygonRings,
              rings.reduce(0, { $0 + $1.coordinates.count }) <= MapLimits.pathVertices
        else { throw MapValidationError.budgetExceeded }
        self.rings = rings
    }

    var vertexCount: Int { rings.reduce(0) { $0 + $1.coordinates.count } }
}

extension MapPolygon: Hashable {}
extension MapPolygon: Sendable {}
extension MapPolygon: Codable {
    private enum CodingKeys: String, CodingKey { case rings }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(rings: values.decode([MapRing].self, forKey: .rings))
    }
}
