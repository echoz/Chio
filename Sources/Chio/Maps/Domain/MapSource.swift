/// Canonical geometry together with the source facts required to present it.
public struct MapSource {
    public let dataset: MapDataset
    public let metadata: MapSourceMetadata
    public let coverage: MapCoverage

    public init(dataset: MapDataset, metadata: MapSourceMetadata, coverage: MapCoverage) {
        self.dataset = dataset
        self.metadata = metadata
        self.coverage = coverage
    }
}

extension MapSource: Hashable {}
extension MapSource: Sendable {}

extension MapSource: Codable {}
