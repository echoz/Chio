import Foundation

/// Accepts only the spike's normalized GeoJSON schema, with the existing geometry limits.
struct NormalizedGeoJSONMapAdapter {
    let metadata: MapSourceMetadata
    let coverage: MapCoverage
}

extension NormalizedGeoJSONMapAdapter: MapSourceAdapter {
    func adapt(_ input: Data) throws -> MapSource {
        try MapSource(dataset: MapDataset.decodeGeoJSON(input), metadata: metadata, coverage: coverage)
    }
}

extension NormalizedGeoJSONMapAdapter: Sendable {}
