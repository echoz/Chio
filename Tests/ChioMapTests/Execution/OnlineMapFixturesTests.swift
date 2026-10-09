@testable import Chio
@testable import ChioMaps
import Foundation
import Synchronization
import Testing

struct OnlineMapFixturesTests {
    @Test("Normal zoom-fourteen whole tiles retain canonical rejection and checked eastern geometry")
    func normalResolutionWholeTiles() throws {
        let metadata = try MapFixtures.load().openFreeMapSource.metadata
        let entries = try normalResolutionEntries()
        for (tile, data) in entries {
            let adapter = OpenMapTilesAdapter(tile: tile, metadata: metadata)
            switch tile.x {
            case 12917, 12918:
                // Independently counted whole inputs contain 4,219 and 4,797
                // supported parts. Neither may be silently truncated to fit.
                #expect(throws: MapValidationError.budgetExceeded) { try adapter.adapt(data) }
            case 12919:
                let whole = try adapter.adapt(data)
                #expect(whole.dataset.features.count == 384)
                #expect(whole.dataset.vertexCount == 3_365)
            case 12920:
                let whole = try adapter.adapt(data)
                #expect(whole.dataset.features.count == 47)
                #expect(whole.dataset.vertexCount == 438)
            case 12921:
                let whole = try adapter.adapt(data)
                #expect(whole.dataset.features.count == 1)
                #expect(whole.dataset.vertexCount == 5)
            default: Issue.record("Unexpected normal-resolution fixture address")
            }
        }
    }

    @Test("Normal-resolution acquisition preserves all admitted original parts and truthful regional coverage")
    func normalResolutionAcquisition() async throws {
        let metadata = try MapFixtures.load().openFreeMapSource.metadata
        let entries = try normalResolutionEntries()
        let bytes = Dictionary(uniqueKeysWithValues: entries)
        let calls = Mutex<[MapTileCoordinate]>([])
        let source = try OpenMapTilesSource(template: "https://example.test/{z}/{x}/{y}.pbf",
                                            zoomRange: 0...14, metadata: metadata)
        let loader = MapTileLoader(source: source, transport: { url, _ in
            let parts = url.deletingPathExtension().pathComponents
            let tile = try MapTileCoordinate(zoom: Int(parts[1])!, x: Int(parts[2])!, y: Int(parts[3])!)
            calls.withLock { $0.append(tile) }
            guard let data = bytes[tile] else { throw MapTileLoader.LoadingError.httpStatus(404) }
            return .init(data: data, headers: ["cache-control": "max-age=60"])
        })
        let viewport = try MapViewport(columns: 98, rows: 19)
        let initialRequest = try MapTileRequest(camera: .init(center: .init(latitude: 1.289, longitude: 103.866),
                                                             longitudeSpan: 0.03), viewport: viewport)
        let panRequest = try MapTileRequest(camera: .init(center: .init(latitude: 1.289, longitude: 103.8948),
                                                         longitudeSpan: 0.03), viewport: viewport)
        let markers = MapFixtures.Scene.street.overlays.markers
        let merlion = try #require(markers.first { $0.id == "merlion" })
        let gardens = try #require(markers.first { $0.id == "gardens" })
        #expect(merlion.coordinate == (try .init(latitude: 1.2868, longitude: 103.8545)))
        #expect(gardens.coordinate == (try .init(latitude: 1.2816, longitude: 103.8636)))
        let merlionRequest = try MapTileRequest(camera: .init(center: merlion.coordinate,
                                                             longitudeSpan: 0.03), viewport: viewport)
        let gardensRequest = try MapTileRequest(camera: .init(center: gardens.coordinate,
                                                             longitudeSpan: 0.03), viewport: viewport)
        // Independent protobuf command decoding counted complete multipart parts
        // using original integer-coordinate projection and inclusive exterior/path
        // bounding boxes. Admitted polygons count every original hole vertex.
        let scenarios: [(MapTileRequest, [(Int, Int, Int)])] = [
            (initialRequest, [(12918, 904, 7_518), (12919, 75, 1_144)]),
            (panRequest, [(12919, 27, 195), (12920, 3, 79), (12921, 1, 5)]),
            (merlionRequest, [(12917, 433, 3_569), (12918, 2_836, 18_833), (12919, 66, 943)]),
            (gardensRequest, [(12918, 1_138, 8_102), (12919, 138, 1_463)]),
        ]
        var snapshots: [MapTileSnapshot] = []
        for (request, expected) in scenarios {
            for (x, features, vertices) in expected {
                let tile = try MapTileCoordinate(zoom: 14, x: x, y: 8133)
                let data = try #require(bytes[tile])
                let admitted = try OpenMapTilesAdapter(tile: tile, metadata: metadata).adapt(data, intersecting: request)
                #expect(admitted.features.count == features)
                #expect(admitted.vertexCount == vertices)
            }
            let snapshot = try await loader.load(request)
            #expect(snapshot.request == request)
            #expect(snapshot.requestedZoom == 14 && snapshot.attainedZoom == 14)
            #expect(snapshot.source.dataset.features.count == expected.reduce(0) { $0 + $1.1 })
            #expect(snapshot.source.dataset.vertexCount == expected.reduce(0) { $0 + $1.2 })
            guard case .tiled(let coverage) = snapshot.source.coverage else {
                Issue.record("Expected retained regional tile coverage"); return
            }
            #expect(coverage.region == request)
            #expect(coverage.covers(request))
            #expect(coverage.tiles.map(\.x) == expected.map { $0.0 })
            #expect(coverage.tiles.allSatisfy { $0.zoom == 14 && $0.y == 8133 })
            snapshots.append(snapshot)
        }
        guard case .tiled(let initialCoverage) = snapshots[0].source.coverage,
              case .tiled(let panCoverage) = snapshots[1].source.coverage else {
            Issue.record("Expected initial and adjacent regional coverage"); return
        }
        #expect(!initialCoverage.covers(panRequest))
        #expect(!initialCoverage.covers(merlionRequest))
        #expect(!panCoverage.contains(initialRequest.camera.center))
        let outsideRetainedRegion = try MapCoordinate(latitude: 1.289, longitude: 103.844)
        let acquiredWesternTile = try MapTileCoordinate(zoom: 14, x: 12918, y: 8133)
        #expect(try acquiredWesternTile.coverage.contains(outsideRetainedRegion))
        #expect(!initialCoverage.contains(outsideRetainedRegion))
        // All five original z14 inputs are acquired once. Overlapping regions
        // reuse bytes without claiming their earlier culling as whole-tile data.
        #expect(calls.withLock { $0.count } == 5)
        #expect(calls.withLock { Set($0) } == Set(entries.map { $0.0 }))
    }

    private func normalResolutionEntries() throws -> [(MapTileCoordinate, Data)] {
        try (12917...12921).map { x in
            let url = try #require(Bundle.module.url(forResource: "14-\(x)-8133", withExtension: "pbf",
                                                     subdirectory: "Fixtures/OnlineTiles"))
            return (try MapTileCoordinate(zoom: 14, x: x, y: 8133), try Data(contentsOf: url))
        }
    }

    @Test("Complete retained tiles preserve canonical limits while viewport acquisition keeps all visible parts")
    func retainedTiles() async throws {
        let metadata = try MapFixtures.load().openFreeMapSource.metadata
        let entries = try [3228, 3229, 3230].map { x in
            let url = try #require(Bundle.module.url(forResource: "12-\(x)-2033", withExtension: "pbf",
                                                     subdirectory: "Fixtures/OnlineTiles"))
            return (try MapTileCoordinate(zoom: 12, x: x, y: 2033), try Data(contentsOf: url))
        }
        for (address, data) in entries {
            let adapter = OpenMapTilesAdapter(tile: address, metadata: metadata)
            if address.x == 3230 {
                let whole = try adapter.adapt(data)
                #expect(whole.dataset.features.count == 2_721)
                #expect(whole.dataset.vertexCount == 6_871)
            } else {
                #expect(throws: MapValidationError.budgetExceeded) { try adapter.adapt(data) }
            }
        }
        let bytes = Dictionary(uniqueKeysWithValues: entries)
        let source = try OpenMapTilesSource(template: "https://example.test/{z}/{x}/{y}.pbf",
                                            zoomRange: 12...12, metadata: metadata)
        let loader = MapTileLoader(source: source, transport: { url, _ in
            let parts = url.deletingPathExtension().pathComponents
            let tile = try MapTileCoordinate(zoom: Int(parts[1])!, x: Int(parts[2])!, y: Int(parts[3])!)
            guard let data = bytes[tile] else { throw MapTileLoader.LoadingError.httpStatus(404) }
            return .init(data: data, headers: ["cache-control": "max-age=60"])
        })
        let camera = try MapCamera(center: .init(latitude: 1.289, longitude: 103.866), longitudeSpan: 0.03)
        let viewport = try MapViewport(columns: 98, rows: 19)
        let initial = try await loader.load(.init(camera: camera, viewport: viewport))
        // Independently counted from original integer commands and inclusive
        // projected bounds, before any simplification, including retained holes.
        #expect(initial.source.dataset.features.count == 345)
        #expect(initial.source.dataset.vertexCount == 2_071)
        #expect(initial.attainedZoom == 12)
        let moved = try MapTileRequest(camera: .init(center: .init(latitude: 1.289, longitude: 103.8948),
                                                   longitudeSpan: 0.03), viewport: viewport)
        let adjacent = try await loader.load(moved)
        #expect(adjacent.source.dataset.features.count == 29)
        #expect(adjacent.source.dataset.vertexCount == 1_056)
        guard case .tiled(let oldCoverage) = initial.source.coverage,
              case .tiled(let newCoverage) = adjacent.source.coverage else {
            Issue.record("Expected region-bounded tile coverage"); return
        }
        #expect(oldCoverage.tiles.count == 1 && !oldCoverage.covers(moved))
        #expect(newCoverage.tiles.count == 2 && newCoverage.covers(moved))
    }
}
