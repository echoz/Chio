/// Canonical geometry together with the source facts required to present it.
struct MapSource {
    let dataset: MapDataset
    let metadata: MapSourceMetadata
    let coverage: MapCoverage
}

extension MapSource: Hashable {}
extension MapSource: Sendable {}
