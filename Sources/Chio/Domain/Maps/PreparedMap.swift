/// A finite immutable rendering snapshot. No persisted representation is promised.
struct PreparedMap {
    let lines: [Line]
    let polygons: [Polygon]
    let labels: [Label]
    let statistics: Statistics

    struct Point {
        let x: Double
        let y: Double
    }

    struct Line {
        let featureID: String
        let kind: MapFeature.Kind
        let points: [Point]
    }

    struct Polygon {
        let featureID: String
        let kind: MapFeature.Kind
        let rings: [[Point]]
    }

    struct Label {
        let featureID: String
        let kind: MapFeature.Kind
        let text: String
        let position: Point
    }

    struct Statistics {
        let sourceVertices: Int
        let preparedVertices: Int
        let visibleFeatures: Int
    }
}

extension PreparedMap: Hashable {}
extension PreparedMap: Sendable {}

extension PreparedMap.Point: Hashable {}
extension PreparedMap.Point: Sendable {}

extension PreparedMap.Line: Hashable {}
extension PreparedMap.Line: Sendable {}

extension PreparedMap.Polygon: Hashable {}
extension PreparedMap.Polygon: Sendable {}

extension PreparedMap.Label: Hashable {}
extension PreparedMap.Label: Sendable {}

extension PreparedMap.Statistics: Hashable {}
extension PreparedMap.Statistics: Sendable {}
