/// The bounded geometry alternatives supported by offline maps.
public enum MapGeometry {
    case polyline(MapPolyline)
    case polygon(MapPolygon)

    public var vertexCount: Int {
        switch self {
        case .polyline(let line): line.coordinates.count
        case .polygon(let polygon): polygon.vertexCount
        }
    }
}

extension MapGeometry: Hashable {}
extension MapGeometry: Codable {}
extension MapGeometry: Sendable {}
