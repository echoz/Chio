import Foundation

extension OpenMapTilesSource {
    /// Explicit bounded discovery. The observed catalog path records what was
    /// requested; OpenFreeMap may serve newer bytes under an older version path.
    public static func fetchOpenFreeMap() async throws -> Self {
        try await fetchOpenFreeMap(transport: { try await MapHTTPClient.fetch($0, resource: $1) })
    }

    static func fetchOpenFreeMap(transport: MapHTTPClient.Transport) async throws -> Self {
        let response = try await transport(URL(string: "https://tiles.openfreemap.org/planet")!, .catalog)
        try Task.checkCancellation()
        guard response.data.count <= MapHTTPClient.Resource.catalog.limit else { throw MapTileLoader.LoadingError.responseTooLarge }
        let catalog: TileJSON
        do { catalog = try JSONDecoder().decode(TileJSON.self, from: response.data) }
        catch { throw MapTileLoader.LoadingError.invalidCatalog }
        guard (0...22).contains(catalog.minzoom), (catalog.minzoom...22).contains(catalog.maxzoom) else {
            throw MapTileLoader.LoadingError.invalidCatalog
        }
        for template in catalog.tiles {
            guard template.utf8.count <= 1_024,
                  let url = URL(string: template.replacingOccurrences(of: "{z}", with: "0")
                    .replacingOccurrences(of: "{x}", with: "0").replacingOccurrences(of: "{y}", with: "0")),
                  url.scheme?.lowercased() == "https", url.host?.lowercased() == "tiles.openfreemap.org",
                  url.port == nil || url.port == 443 else { continue }
            guard let metadata = try? MapSourceMetadata(
                attribution: "OpenFreeMap · OpenMapTiles · © OpenStreetMap contributors",
                attributionURL: URL(string: "https://openfreemap.org"), license: "ODbL",
                licenseURL: URL(string: "https://opendatacommons.org/licenses/odbl/1-0/")!,
                sourceURL: URL(string: "https://tiles.openfreemap.org/planet")!, sourceRevision: template) else { continue }
            if let source = try? OpenMapTilesSource(template: template, zoomRange: catalog.minzoom...catalog.maxzoom, metadata: metadata) {
                return source
            }
        }
        throw MapTileLoader.LoadingError.invalidCatalog
    }

    private struct TileJSON: Decodable {
        let tiles: [String]
        let minzoom: Int
        let maxzoom: Int
    }
}
