@testable import Chio
import Foundation
import Synchronization
import Testing

struct MapTileLoaderPackTests {
    @Test("Pack loads preserve coverage and metadata across reopen without HTTP or freshness clocks")
    func reopenWithoutFreshness() async throws {
        let file = location()
        defer { try? FileManager.default.removeItem(at: file) }
        let plan = try worldPlan(zoom: 1)
        let metadata = try metadata()
        let pack = try await MapTilePack.create(at: file, plan: plan, metadata: metadata) { _ in Data() }
        let clock = Mutex<TimeInterval>(0)
        let loader = MapTileLoader(pack: pack, now: { clock.withLock { $0 } }, wallNow: {
            Issue.record("Immutable pack retention must not consult UTC")
            return .nan
        })
        let request = try worldRequest()
        let first = try await loader.load(request)
        #expect(first.source.metadata == metadata)
        #expect(first.source.dataset.features.isEmpty)
        #expect(first.source.coverage == .tiled(try MapTileCoverage(tiles: plan.tiles, region: request)))
        clock.withLock { $0 = 10_000 }
        #expect(try await loader.load(request) == first)
        #expect(await loader.statistics().maximumInFlight == 0)
        #expect(await loader.statistics().cacheEntries == 4)
        await pack.close()

        let reopened = try MapTilePack.open(at: file)
        #expect(try await MapTileLoader(pack: reopened).load(request) == first)
        await reopened.close()
    }

    @Test("Closing a pack rejects even a fully cached viewport")
    func closedPack() async throws {
        let file = location()
        defer { try? FileManager.default.removeItem(at: file) }
        let pack = try await MapTilePack.create(at: file, plan: worldPlan(zoom: 1), metadata: metadata()) { _ in Data() }
        let loader = MapTileLoader(pack: pack)
        _ = try await loader.load(worldRequest())
        await pack.close()
        await #expect(throws: MapTilePack.PackError.closed) { try await loader.load(worldRequest()) }
    }

    @Test("Missing coverage rejects a complete viewport rather than publishing a partial map")
    func unavailableCoverage() async throws {
        let file = location()
        defer { try? FileManager.default.removeItem(at: file) }
        let bounds = try MapCoverage.Bounds(southwest: MapCoordinate(latitude: 5, longitude: 5),
                                            northeast: MapCoordinate(latitude: 15, longitude: 15))
        let plan = try MapTilePackPlan(bounds: bounds, zoomRange: 1...1)
        #expect(plan.tiles.count == 1)
        let pack = try await MapTilePack.create(at: file, plan: plan, metadata: metadata()) { _ in Data() }
        let loader = MapTileLoader(pack: pack)
        await #expect(throws: MapTileLoader.LoadingError.outsidePackCoverage) {
            try await loader.load(worldRequest())
        }
        #expect(await loader.statistics().maximumInFlight == 0)
        await pack.close()
    }

    @Test("Checksum-valid malformed MVT remains a decoding error")
    func malformedTile() async throws {
        let file = location()
        defer { try? FileManager.default.removeItem(at: file) }
        let pack = try await MapTilePack.create(at: file, plan: worldPlan(zoom: 1), metadata: metadata()) { _ in Data([0xff]) }
        let loader = MapTileLoader(pack: pack)
        await #expect(throws: OpenMapTilesAdapter.ValidationError.malformedWire) {
            try await loader.load(worldRequest())
        }
        #expect(await loader.statistics().maximumInFlight == 0)
        await pack.close()
    }

    @Test("Pack memory remains bounded and eviction leaves durable bytes unchanged")
    func entryEviction() async throws {
        let file = location()
        defer { try? FileManager.default.removeItem(at: file) }
        let plan = try worldPlan(zoom: 4)
        let pack = try await MapTilePack.create(at: file, plan: plan, metadata: metadata()) { _ in Data() }
        let before = try Data(contentsOf: file)
        let loader = MapTileLoader(pack: pack)
        let viewport = try MapViewport(columns: 80, rows: 20)
        let requests = try plan.tiles.prefix(70).map { tile in
            let center = try tile.coordinate(interpolatedX: 0.5, interpolatedY: 0.5, extent: 1)
            return MapTileRequest(camera: try MapCamera(center: center, longitudeSpan: 0.01), viewport: viewport)
        }
        let first = try await loader.load(requests[0])
        for request in requests.dropFirst() {
            _ = try await loader.load(request)
            #expect(await loader.statistics().cacheEntries <= 64)
        }
        #expect(await loader.statistics().cacheEntries == 64)
        #expect(try await loader.load(requests[0]) == first)
        #expect(try Data(contentsOf: file) == before)
        await pack.close()
    }

    @Test("Large retained pack tiles obey the same thirty-two MiB memory budget")
    func byteEviction() async throws {
        let file = location()
        defer { try? FileManager.default.removeItem(at: file) }
        let bytes = paddingTile(bytes: 12 * 1_024 * 1_024)
        let pack = try await MapTilePack.create(at: file, plan: worldPlan(zoom: 1), metadata: metadata()) { _ in bytes }
        let loader = MapTileLoader(pack: pack)
        _ = try await loader.load(worldRequest())
        let statistics = await loader.statistics()
        #expect(statistics.cacheBytes <= 32 * 1_024 * 1_024)
        #expect(statistics.cacheEntries == 2)
        await pack.close()
    }

    @Test("Separate packs with identical provenance cannot share cached bytes")
    func packIdentity() async throws {
        let firstFile = location(), secondFile = location()
        defer {
            try? FileManager.default.removeItem(at: firstFile)
            try? FileManager.default.removeItem(at: secondFile)
        }
        let plan = try worldPlan(zoom: 1), metadata = try metadata()
        let first = try await MapTilePack.create(at: firstFile, plan: plan, metadata: metadata) { _ in Data() }
        let second = try await MapTilePack.create(at: secondFile, plan: plan, metadata: metadata) { _ in Data([0xff]) }
        _ = try await MapTileLoader(pack: first).load(worldRequest())
        await #expect(throws: OpenMapTilesAdapter.ValidationError.malformedWire) {
            try await MapTileLoader(pack: second).load(worldRequest())
        }
        await first.close()
        await second.close()
    }

    private func location() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("chio-pack-loader-\(UUID().uuidString).chiomap")
    }

    private func metadata() throws -> MapSourceMetadata {
        let url = URL(string: "https://example.test")!
        return try MapSourceMetadata(attribution: "Test tiles", license: "Fixture", licenseURL: url,
                                     sourceURL: url, sourceRevision: "same-provider-revision")
    }

    private func worldPlan(zoom: Int) throws -> MapTilePackPlan {
        let bounds = try MapCoverage.Bounds(southwest: MapCoordinate(latitude: -85, longitude: -180),
                                            northeast: MapCoordinate(latitude: 85, longitude: 180))
        return try MapTilePackPlan(bounds: bounds, zoomRange: zoom...zoom)
    }

    private func worldRequest() throws -> MapTileRequest {
        try MapTileRequest(camera: MapCamera(center: MapCoordinate(latitude: 0, longitude: 0), longitudeSpan: 360),
                           viewport: MapViewport(columns: 100, rows: 30))
    }

    private func paddingTile(bytes: Int) -> Data {
        var length = bytes
        var data = Data([0x0a])
        while length >= 128 {
            data.append(UInt8(length & 127) | 128)
            length >>= 7
        }
        data.append(UInt8(length))
        data.append(Data(repeating: 0, count: bytes))
        return data
    }
}
