@testable import Chio
@testable import ChioMaps
import Foundation
import Synchronization
import Testing

struct PersistentMapGeometryTests {
    @Test("Reopened raw street tiles repeat viewport admission and preserve whole geometry")
    func retainedTilesRecomputeCoverage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("chio-geometry-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixtures = try MapFixtures.load()
        let source = try OpenMapTilesSource(template: "https://example.test/{z}/{x}/{y}.pbf", zoomRange: 12...12,
                                            metadata: fixtures.openFreeMapSource.metadata)
        let dataURL = try #require(Bundle.module.url(forResource: "12-3229-2033", withExtension: "pbf",
                                                     subdirectory: "Fixtures/OnlineTiles"))
        let data = try Data(contentsOf: dataURL)
        let calls = Mutex(0)
        let cache = try MapTileCache.open(directory: directory, source: source)
        let first = MapTileLoader(cache: cache, transport: { url, _ in
            #expect(url.path == "/12/3229/2033.pbf")
            calls.withLock { $0 += 1 }
            return MapHTTPClient.Response(data: data, headers: ["cache-control": "max-age=1800"])
        })
        let viewport = try MapViewport(columns: 98, rows: 19)
        let original = try MapTileRequest(
            camera: MapCamera(center: MapCoordinate(latitude: 1.289, longitude: 103.866), longitudeSpan: 0.03),
            viewport: viewport)
        let initial = try await first.load(original)
        #expect(initial.source.dataset.features.count == 345)
        #expect(initial.source.dataset.vertexCount == 2_071)
        #expect(calls.withLock { $0 } == 1)
        await cache.close()

        let reopened = try MapTileCache.open(directory: directory, source: source)
        let second = MapTileLoader(cache: reopened, transport: { _, _ in
            Issue.record("Both viewports fit the persisted tile")
            throw MapTileLoader.LoadingError.httpStatus(503)
        })
        #expect(try await second.load(original) == initial)
        let panned = try MapTileRequest(
            camera: MapCamera(center: MapCoordinate(latitude: 1.289, longitude: 103.870), longitudeSpan: 0.03),
            viewport: viewport)
        let moved = try await second.load(panned)
        let tile = try MapTileCoordinate(zoom: 12, x: 3229, y: 2033)
        let admitted = try OpenMapTilesAdapter(tile: tile, metadata: source.metadata).adapt(data, intersecting: panned)
        #expect(moved.source.dataset.features == admitted.features)
        #expect(moved.source.dataset != initial.source.dataset)
        #expect(moved.source.metadata == source.metadata)
        #expect(moved.source.coverage == .tiled(try MapTileCoverage(tiles: [tile], region: panned)))
        guard case .tiled(let previousCoverage) = initial.source.coverage else {
            Issue.record("Expected tile coverage"); await reopened.close(); return
        }
        #expect(!previousCoverage.covers(panned))
        await reopened.close()
    }
}
