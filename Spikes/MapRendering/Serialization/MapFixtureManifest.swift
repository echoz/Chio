import Foundation

/// Reads the existing offline fixture manifest without changing its representation.
struct MapFixtureManifest {
    let worldMetadata: MapSourceMetadata
    let streetMetadata: MapSourceMetadata
    let streetBounds: MapCoverage.Bounds
}

extension MapFixtureManifest: Decodable {
    private enum CodingKeys: String, CodingKey { case sources }
    private enum SourceKeys: String, CodingKey { case world, singapore }
    private enum FieldKeys: String, CodingKey {
        case attribution, attributionURL, license, licenseURL, sourceURL
        case sourceCommit, sourceTimestamp, queryBounds
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let sources = try values.nestedContainer(keyedBy: SourceKeys.self, forKey: .sources)
        let world = try sources.nestedContainer(keyedBy: FieldKeys.self, forKey: .world)
        let street = try sources.nestedContainer(keyedBy: FieldKeys.self, forKey: .singapore)
        worldMetadata = try Self.metadata(from: world, revisionKey: .sourceCommit)
        streetMetadata = try Self.metadata(from: street, revisionKey: .sourceTimestamp)
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
