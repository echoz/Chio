/// A finite immutable rendering snapshot. No persisted representation is promised.
struct PreparedMap {
    let lines: [Line]
    let polygons: [Polygon]
    let labels: [Label]
    let statistics: Statistics

    struct Point: Hashable, Sendable {
        let x: Double
        let y: Double
    }

    struct Line: Hashable, Sendable {
        let featureID: String
        let kind: MapFeature.Kind
        let points: [Point]
    }

    struct Polygon: Hashable, Sendable {
        let featureID: String
        let kind: MapFeature.Kind
        let rings: [[Point]]
    }

    struct Label: Hashable, Sendable {
        let featureID: String
        let kind: MapFeature.Kind
        let text: String
        let position: Point
    }

    struct Statistics: Hashable, Sendable {
        let sourceVertices: Int
        let preparedVertices: Int
        let visibleFeatures: Int
    }
}

extension PreparedMap: Hashable {}
extension PreparedMap: Sendable {}
