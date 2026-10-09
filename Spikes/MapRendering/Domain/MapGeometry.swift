/// Only the two geometry alternatives used by the flattened local fixtures.
enum MapGeometry {
    case polyline(MapPolyline)
    case polygon(MapPolygon)

    var vertexCount: Int {
        switch self {
        case .polyline(let line): line.coordinates.count
        case .polygon(let polygon): polygon.vertexCount
        }
    }
}

extension MapGeometry: Hashable {}
extension MapGeometry: Codable {}
extension MapGeometry: Sendable {}
