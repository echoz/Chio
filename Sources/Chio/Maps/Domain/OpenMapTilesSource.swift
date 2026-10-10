import Foundation

/// Explicit endpoint configuration for uncompressed OpenMapTiles-compatible MVT.
/// URL construction is pure and does not acquire tiles or discover provider metadata.
public struct OpenMapTilesSource {
    public let template: String
    public let zoomRange: ClosedRange<Int>
    public let metadata: MapSourceMetadata

    public init(template: String, zoomRange: ClosedRange<Int>, metadata: MapSourceMetadata) throws {
        guard template.utf8.count <= 1_024, zoomRange.lowerBound >= 0, zoomRange.upperBound <= 22,
              ["{z}", "{x}", "{y}"].allSatisfy({ template.components(separatedBy: $0).count == 2 })
        else { throw MapValidationError.invalidTileSource }
        let stripped = template.replacingOccurrences(of: "{z}", with: "0")
            .replacingOccurrences(of: "{x}", with: "0").replacingOccurrences(of: "{y}", with: "0")
        guard !stripped.contains("{"), !stripped.contains("}"),
              let original = URLComponents(string: template),
              ["{z}", "{x}", "{y}"].allSatisfy({ original.path.components(separatedBy: $0).count == 2 }),
              let components = URLComponents(string: stripped),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              !(components.host ?? "").isEmpty,
              components.user == nil, components.password == nil, components.fragment == nil,
              let url = components.url, url.baseURL == nil
        else { throw MapValidationError.invalidTileSource }
        self.template = template
        self.zoomRange = zoomRange
        self.metadata = metadata
    }

    public func url(for tile: MapTileCoordinate) throws -> URL {
        guard zoomRange.contains(tile.zoom),
              let url = URL(string: template.replacingOccurrences(of: "{z}", with: String(tile.zoom))
                .replacingOccurrences(of: "{x}", with: String(tile.x))
                .replacingOccurrences(of: "{y}", with: String(tile.y)))
        else { throw MapValidationError.invalidTileSource }
        return url
    }
}

extension OpenMapTilesSource: Hashable {}
extension OpenMapTilesSource: Sendable {}
extension OpenMapTilesSource: Codable {
    private enum CodingKeys: String, CodingKey { case template, zoomRange, metadata }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(template: values.decode(String.self, forKey: .template),
                      zoomRange: values.decode(ClosedRange<Int>.self, forKey: .zoomRange),
                      metadata: values.decode(MapSourceMetadata.self, forKey: .metadata))
    }
}
