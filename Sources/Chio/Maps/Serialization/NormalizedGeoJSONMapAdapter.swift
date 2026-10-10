import Foundation

/// Accepts only the normalized GeoJSON schema, with the existing geometry limits.
public struct NormalizedGeoJSONMapAdapter {
    public let metadata: MapSourceMetadata
    public let coverage: MapCoverage

    public init(metadata: MapSourceMetadata, coverage: MapCoverage) {
        self.metadata = metadata
        self.coverage = coverage
    }
}

extension NormalizedGeoJSONMapAdapter: MapSourceAdapter {
    public func adapt(_ input: Data) throws -> MapSource {
        try MapSource(dataset: MapDataset.decodeGeoJSON(input), metadata: metadata, coverage: coverage)
    }
}

extension NormalizedGeoJSONMapAdapter: Sendable {}
