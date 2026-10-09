import Chio
import Foundation

/// Reads provider provenance and fixture coordinates at the executable boundary.
struct MapFixtureManifest {
    let worldMetadata: MapSourceMetadata
    let streetMetadata: MapSourceMetadata
    let streetBounds: MapCoverage.Bounds
    let openFreeMapMetadata: MapSourceMetadata
    let openFreeMapTile: MapTileCoordinate
}

extension MapFixtureManifest: Decodable {
    private enum CodingKeys: String, CodingKey { case sources }
    private enum SourceKeys: String, CodingKey { case world, singapore, openfreemap }
    private enum FieldKeys: String, CodingKey {
        case attribution, attributionURL, license, licenseURL, sourceURL
        case sourceCommit, sourceTimestamp, sourceRevision, queryBounds, tile
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let sources = try values.nestedContainer(keyedBy: SourceKeys.self, forKey: .sources)
        let world = try sources.nestedContainer(keyedBy: FieldKeys.self, forKey: .world)
        let street = try sources.nestedContainer(keyedBy: FieldKeys.self, forKey: .singapore)
        worldMetadata = try Self.metadata(from: world, revisionKey: .sourceCommit)
        streetMetadata = try Self.metadata(from: street, revisionKey: .sourceTimestamp)
        let openFreeMap = try sources.nestedContainer(keyedBy: FieldKeys.self, forKey: .openfreemap)
        openFreeMapMetadata = try Self.metadata(from: openFreeMap, revisionKey: .sourceRevision)
        openFreeMapTile = try openFreeMap.decode(MapTileCoordinate.self, forKey: .tile)
        var bounds = try street.nestedUnkeyedContainer(forKey: .queryBounds)
        let west = try bounds.decode(Double.self)
        let south = try bounds.decode(Double.self)
        let east = try bounds.decode(Double.self)
        let north = try bounds.decode(Double.self)
        guard bounds.isAtEnd else { throw MapCoverage.ValidationError.invalidBounds }
        streetBounds = try MapCoverage.Bounds(
            southwest: MapCoordinate(latitude: south, longitude: west),
            northeast: MapCoordinate(latitude: north, longitude: east))
    }

    private static func metadata(from values: KeyedDecodingContainer<FieldKeys>,
                                 revisionKey: FieldKeys) throws -> MapSourceMetadata {
        try MapSourceMetadata(attribution: values.decode(String.self, forKey: .attribution),
                              attributionURL: values.decodeIfPresent(URL.self, forKey: .attributionURL),
                              license: values.decode(String.self, forKey: .license),
                              licenseURL: values.decode(URL.self, forKey: .licenseURL),
                              sourceURL: values.decode(URL.self, forKey: .sourceURL),
                              sourceRevision: values.decode(String.self, forKey: revisionKey))
    }
}
