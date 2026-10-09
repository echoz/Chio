import Foundation

/// Terminal cartographic selection, separate from the retained source geometry.
enum MapDetail: String {
    case silhouette
    case minimal
    case abstract
    case source

    var less: MapDetail {
        switch self {
        case .silhouette, .minimal: .silhouette
        case .abstract: .minimal
        case .source: .abstract
        }
    }

    var more: MapDetail {
        switch self {
        case .silhouette: .minimal
        case .minimal: .abstract
        case .abstract, .source: .source
        }
    }

    var next: MapDetail { self == .source ? .silhouette : more }

    var levelNumber: Int {
        switch self {
        case .silhouette: 1
        case .minimal: 2
        case .abstract: 3
        case .source: 4
        }
    }

    /// Provisional deviation in terminal-column widths, measured in physical space.
    /// Abstract and source retain the accepted polygon geometry exactly.
    func shapeTolerance(for kind: MapFeature.Kind) -> Double {
        guard kind == .land || kind == .water else { return 0 }
        switch self {
        case .silhouette: return 1.5
        case .minimal: return 0.75
        case .abstract, .source: return 0
        }
    }

    func admits(_ kind: MapFeature.Kind, camera: MapCamera, viewport: MapViewport) -> Bool {
        switch self {
        case .source:
            return true
        case .silhouette:
            return kind == .land || kind == .water
        case .minimal:
            return kind == .land || kind == .water || kind == .primaryRoad
        case .abstract:
            switch kind {
            case .building:
                return false
            case .road:
                // Minor streets need both useful scale and enough room to read a network.
                // Mercator scale varies with latitude; this is ground distance per column.
                let metresPerCell = camera.longitudeSpan / Double(viewport.columns)
                    * .pi / 180 * 6_378_137 * cos(camera.center.latitude * .pi / 180)
                return metresPerCell <= 12 && viewport.columns >= 58 && viewport.rows >= 16
            case .land, .water, .park, .primaryRoad:
                return true
            }
        }
    }

    func admitsArea(_ visibleCellArea: Double, kind: MapFeature.Kind) -> Bool {
        switch self {
        case .source:
            return true
        case .silhouette, .minimal:
            switch kind {
            case .land: return visibleCellArea >= 2
            case .water: return visibleCellArea >= 4
            case .primaryRoad: return self == .minimal
            case .park, .building, .road: return false
            }
        case .abstract:
            switch kind {
            case .land: return visibleCellArea >= 0.5
            case .water: return visibleCellArea >= 1
            case .park: return visibleCellArea >= 6
            case .building: return false
            case .road, .primaryRoad: return true
            }
        }
    }

    func outlines(_ kind: MapFeature.Kind) -> Bool {
        self == .source || kind != .park
    }

    func labelLimit(columns: Int, rows: Int) -> Int {
        switch self {
        case .silhouette: min(2, max(1, columns * rows / 800))
        case .minimal: min(4, max(1, columns * rows / 500))
        case .abstract: min(8, max(1, columns * rows / 300))
        case .source: max(1, columns * rows / 100)
        }
    }

    var labelRowGap: Int {
        switch self {
        case .silhouette, .minimal: 3
        case .abstract: 2
        case .source: 1
        }
    }

    var labelColumnGap: Int {
        switch self {
        case .silhouette, .minimal: 6
        case .abstract: 4
        case .source: 2
        }
    }
}

extension MapDetail: CaseIterable {}
extension MapDetail: Hashable {}
extension MapDetail: Codable {}
extension MapDetail: Sendable {}
