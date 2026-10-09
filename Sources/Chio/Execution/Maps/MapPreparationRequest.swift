/// Geometry inputs that must agree before an asynchronous drawing can be shown.
struct MapPreparationRequest {
    let dataset: MapDataset
    let camera: MapCamera
    let viewport: MapViewport
    let detail: MapDetail
    let routes: [MapRoute]
    let fills: Bool
}

extension MapPreparationRequest: Hashable {}
extension MapPreparationRequest: Sendable {}
