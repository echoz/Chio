import Foundation

/// Terminal cartographic selection, separate from the retained source geometry.
enum MapDetail: String {
    case abstract
    case source

    func admits(_ kind: MapFeature.Kind, camera: MapCamera, viewport: MapViewport) -> Bool {
        guard self == .abstract else { return true }
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

    func admitsArea(_ visibleCellArea: Double, kind: MapFeature.Kind) -> Bool {
        guard self == .abstract else { return true }
        switch kind {
        case .land: return visibleCellArea >= 0.5
        case .water: return visibleCellArea >= 1
        case .park: return visibleCellArea >= 6
        case .building: return false
        case .road, .primaryRoad: return true
        }
    }

    func outlines(_ kind: MapFeature.Kind) -> Bool {
        self == .source || kind != .park
    }
}

extension MapDetail: Hashable {}
extension MapDetail: Codable {}
extension MapDetail: Sendable {}
