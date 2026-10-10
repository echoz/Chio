import Chio
import Foundation

/// Explicit fixture acquisition; this example never downloads a pack.
enum MapExamplePack {
    static func writeWorld(at file: URL) async throws {
        let bounds = try MapCoverage.Bounds(
            southwest: MapCoordinate(latitude: -85, longitude: -180),
            northeast: MapCoordinate(latitude: 85, longitude: 180))
        let plan = try MapTilePackPlan(bounds: bounds, zoomRange: 1...1)
        guard let manifestURL = Bundle.module.url(forResource: "manifest", withExtension: "json",
                                                  subdirectory: "Fixtures/OnlineTiles") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        let pack = try await MapTilePack.create(at: file, plan: plan, metadata: manifest.metadata) { tile in
            let name = "\(tile.zoom)-\(tile.x)-\(tile.y)"
            guard let url = Bundle.module.url(forResource: name, withExtension: "pbf",
                                             subdirectory: "Fixtures/OnlineTiles") else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try Data(contentsOf: url)
        }
        await pack.close()
    }
    private struct Manifest: Decodable {
        let metadata: MapSourceMetadata
    }
}
