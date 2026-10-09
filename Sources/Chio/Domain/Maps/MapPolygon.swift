import Foundation

/// First ring is the exterior; remaining rings are retained as holes, with no repair.
public struct MapPolygon {
    public let rings: [MapRing]

    public init(rings: [MapRing]) throws {
        guard !rings.isEmpty else { throw MapValidationError.invalidRing }
        guard rings.count <= MapLimits.polygonRings,
              rings.reduce(0, { $0 + $1.coordinates.count }) <= MapLimits.pathVertices
        else { throw MapValidationError.budgetExceeded }
        self.rings = rings
    }

    public var vertexCount: Int { rings.reduce(0) { $0 + $1.coordinates.count } }
}

extension MapPolygon: Hashable {}
extension MapPolygon: Sendable {}
extension MapPolygon: Codable {
    private enum CodingKeys: String, CodingKey { case rings }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        var source = try values.nestedUnkeyedContainer(forKey: .rings)
        var rings: [MapRing] = []
        var vertices = 0
        while !source.isAtEnd {
            guard rings.count < MapLimits.polygonRings, vertices < MapLimits.pathVertices
            else { throw MapValidationError.budgetExceeded }
            let ring = try MapRing(from: source.superDecoder(), vertexLimit: MapLimits.pathVertices - vertices)
            vertices += ring.coordinates.count
            guard vertices <= MapLimits.pathVertices else { throw MapValidationError.budgetExceeded }
            rings.append(ring)
        }
        try self.init(rings: rings)
    }
}
