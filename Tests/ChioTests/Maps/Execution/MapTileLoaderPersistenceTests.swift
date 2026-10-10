@testable import Chio
import Foundation
import Synchronization
import Testing

struct MapTileLoaderPersistenceTests {
    @Test("Reopened raw tiles preserve the snapshot and avoid transport without renewing freshness")
    func reopenAndExpiry() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try source()
        let clock = Mutex<TimeInterval>(1_000)
        let calls = Mutex(0)
        let transport: MapHTTPClient.Transport = { _, _ in
            calls.withLock { $0 += 1 }
            return MapHTTPClient.Response(data: Data(), headers: ["cache-control": "max-age=60", "age": "10"])
        }
        let cache = try MapTileCache.open(directory: directory, source: source, at: 1_000)
        let first = MapTileLoader(cache: cache, transport: transport,
                                  now: { clock.withLock { $0 } }, wallNow: { clock.withLock { $0 } })
        let request = try request()
        let snapshot = try await first.load(request)
        #expect(calls.withLock { $0 } == 4)
        await cache.close()
        let reopened = try MapTileCache.open(directory: directory, source: source, at: 1_025)
        clock.withLock { $0 = 1_025 }
        let second = MapTileLoader(cache: reopened, transport: transport,
                                   now: { clock.withLock { $0 } }, wallNow: { clock.withLock { $0 } })
        #expect(try await second.load(request) == snapshot)
        #expect(calls.withLock { $0 } == 4)
        clock.withLock { $0 = 1_049 }
        #expect(try await second.load(request) == snapshot)
        #expect(calls.withLock { $0 } == 4)
        clock.withLock { $0 = 1_050 }
        _ = try await second.load(request)
        #expect(calls.withLock { $0 } == 8)
        await reopened.close()
    }

    @Test("Persistent memory hits require the cache to remain open")
    func closedCache() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try MapTileCache.open(directory: directory, source: source())
        let loader = MapTileLoader(cache: cache, transport: { _, _ in
            MapHTTPClient.Response(data: Data(), headers: [:])
        })
        _ = try await loader.load(request())
        await cache.close()
        await #expect(throws: MapTileCache.CacheError.closed) { try await loader.load(request()) }
    }

    @Test("Both UTC expiry and monotonic retention constrain memory hits")
    func independentClocks() async throws {
        for scenario in 0..<3 {
            let directory = directory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let wall = Mutex<TimeInterval>(1_000)
            let uptime = Mutex<TimeInterval>(0)
            let calls = Mutex(0)
            let cache = try MapTileCache.open(directory: directory, source: source(), at: 1_000)
            let loader = MapTileLoader(cache: cache, transport: { _, _ in
                calls.withLock { $0 += 1 }
                return MapHTTPClient.Response(data: Data(), headers: ["cache-control": "max-age=60"])
            }, now: { uptime.withLock { $0 } }, wallNow: { wall.withLock { $0 } })
            _ = try await loader.load(request())
            switch scenario {
            case 0: wall.withLock { $0 = 999 }
            case 1: uptime.withLock { $0 = 60 }
            case 2:
                wall.withLock { $0 = 1_040 }; uptime.withLock { $0 = 40 }
                _ = try await loader.load(request())
                #expect(calls.withLock { $0 } == 4)
                wall.withLock { $0 = 1_010 }; uptime.withLock { $0 = 60 }
            default: Issue.record("Unexpected clock scenario")
            }
            _ = await loader.statistics() // Removing expired memory cannot renew disk freshness.
            _ = try await loader.load(request())
            #expect(calls.withLock { $0 } == 8)
            await cache.close()
        }
    }

    @Test("HTTP non-reusable responses never survive a new loader")
    func prohibitedRetention() async throws {
        for directive in ["no-store", "no-cache", "max-age=0", "max-age=garbage"] {
            let directory = directory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let cache = try MapTileCache.open(directory: directory, source: source())
            let calls = Mutex(0)
            let transport: MapHTTPClient.Transport = { _, _ in
                calls.withLock { $0 += 1 }
                return MapHTTPClient.Response(data: Data(), headers: ["cache-control": directive])
            }
            _ = try await MapTileLoader(cache: cache, transport: transport).load(request())
            _ = try await MapTileLoader(cache: cache, transport: transport).load(request())
            #expect(calls.withLock { $0 } == 8)
            await cache.close()
        }
    }

    @Test("Checksum-valid malformed raw responses remain decoder failures after reopen")
    func malformedBytes() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try source()
        let cache = try MapTileCache.open(directory: directory, source: source)
        let first = MapTileLoader(cache: cache, transport: { _, _ in
            MapHTTPClient.Response(data: Data([0xff]), headers: [:])
        })
        await #expect(throws: OpenMapTilesAdapter.ValidationError.malformedWire) {
            try await first.load(request())
        }
        await cache.close()
        let reopened = try MapTileCache.open(directory: directory, source: source)
        let second = MapTileLoader(cache: reopened, transport: { _, _ in
            Issue.record("Fresh raw tiles should be reused, including malformed provider bytes")
            throw MapTileLoader.LoadingError.httpStatus(503)
        })
        await #expect(throws: OpenMapTilesAdapter.ValidationError.malformedWire) {
            try await second.load(request())
        }
        await reopened.close()
    }

    @Test("Sub-precision freshness remains a usable response without persistence")
    func fractionalFreshness() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try MapTileCache.open(directory: directory, source: source(), at: 1_800_000_000)
        let calls = Mutex(0)
        let loader = MapTileLoader(cache: cache, transport: { _, _ in
            calls.withLock { $0 += 1 }
            return MapHTTPClient.Response(data: Data(), headers: ["cache-control": "max-age=0.0000001"])
        }, wallNow: { 1_800_000_000 })
        _ = try await loader.load(request())
        _ = try await loader.load(request())
        #expect(calls.withLock { $0 } == 8)
        await cache.close()
    }

    @Test("A cancelled cache-backed load makes no transport calls")
    func cancelledLoad() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try MapTileCache.open(directory: directory, source: source())
        let loader = MapTileLoader(cache: cache, transport: { _, _ in
            Issue.record("Cancelled load reached transport")
            return MapHTTPClient.Response(data: Data(), headers: [:])
        })
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await loader.load(request())
        }
        await #expect(throws: CancellationError.self) { try await operation.value }
        await cache.close()
    }

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("chio-loader-cache-\(UUID().uuidString)")
    }

    private func source() throws -> OpenMapTilesSource {
        let url = URL(string: "https://example.test")!
        return try OpenMapTilesSource(template: "https://example.test/{z}/{x}/{y}.pbf", zoomRange: 1...1,
                                      metadata: MapSourceMetadata(attribution: "Fixture", license: "Fixture",
                                                                  licenseURL: url, sourceURL: url, sourceRevision: "1"))
    }

    private func request() throws -> MapTileRequest {
        try MapTileRequest(camera: MapCamera(center: MapCoordinate(latitude: 0, longitude: 0), longitudeSpan: 360),
                           viewport: MapViewport(columns: 38, rows: 19))
    }
}
