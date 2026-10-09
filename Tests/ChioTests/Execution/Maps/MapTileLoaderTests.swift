@testable import Chio
import Foundation
import Synchronization
import Testing

struct MapTileLoaderTests {
    @Test("Complete tile plans aggregate without dropping features and cache reusable bytes")
    func completeCoverageAndCache() async throws {
        let calls = Mutex<[URL]>([])
        let clock = Mutex<TimeInterval>(0)
        let loader = MapTileLoader(source: try source(), transport: { url, _ in
            calls.withLock { $0.append(url) }
            return .init(data: Data(), headers: ["cache-control": "max-age=60", "age": "10"])
        }, now: { clock.withLock { $0 } })
        let request = try request()
        let initial = try await loader.load(request)
        let plan = try MapTilePlan(request: request, zoom: initial.attainedZoom)
        #expect(initial.request == request)
        #expect(initial.source.coverage == .tiled(try MapTileCoverage(tiles: plan.tiles, region: request)))
        #expect(initial.source.dataset.features.isEmpty)
        #expect(calls.withLock { $0.count } == plan.tiles.count)
        _ = try await loader.load(request)
        #expect(calls.withLock { $0.count } == plan.tiles.count)
        let statistics = await loader.statistics()
        #expect(statistics.cacheEntries == plan.tiles.count)
        #expect(statistics.cacheBytes == 0 && statistics.inFlight == 0)
        #expect(statistics.maximumInFlight <= 2)
        clock.withLock { $0 = 50 }
        _ = try await loader.load(request)
        #expect(calls.withLock { $0.count } == plan.tiles.count * 2)
    }

    @Test("Canonical aggregation admits exactly four thousand unique features and never truncates")
    func canonicalAggregateBudget() async throws {
        let request = try request(span: 0.001)
        let plan = try MapTilePlan(request: request, zoom: 14)
        #expect(plan.tiles.count == 4)
        let boundedLoader = MapTileLoader(source: try source(range: 14...14), transport: { url, _ in
            .init(data: visibleTransportationTile(url: url, features: 1_000), headers: [:])
        })
        let accepted = try await boundedLoader.load(request)
        #expect(accepted.source.dataset.features.count == 4_000)
        #expect(Set(accepted.source.dataset.features.map(\.id)).count == 4_000)
        #expect(accepted.source.dataset.vertexCount == 8_000)
        let rejectedLoader = MapTileLoader(source: try source(range: 14...14), transport: { url, _ in
            .init(data: visibleTransportationTile(url: url, features: 1_001), headers: [:])
        })
        await #expect(throws: MapValidationError.budgetExceeded) { try await rejectedLoader.load(request) }
        let fallback = MapTileLoader(source: try source(), transport: { url, _ in
            .init(data: visibleTransportationTile(url: url, features: Int(url.pathComponents[2]) == 14 ? 1_001 : 1), headers: [:])
        })
        let lowered = try await fallback.load(request)
        #expect(lowered.requestedZoom == 14 && lowered.attainedZoom == 13)
        #expect(lowered.source.dataset.features.count == 4)
    }

    @Test("Cache freshness respects no-store, no-cache, max-age, Age and the thirty-minute cap")
    func freshness() {
        #expect(MapTileLoader.cacheLifetime(headers: [:]) == 1_800)
        #expect(MapTileLoader.cacheLifetime(headers: ["cache-control": "max-age=86400", "Age": "19335"]) == 1_800)
        #expect(MapTileLoader.cacheLifetime(headers: ["cache-control": "max-age = 60", "Age": "25"]) == 35)
        #expect(MapTileLoader.cacheLifetime(headers: ["Cache-Control": "public, max-age=9999"]) == 1_800)
        #expect(MapTileLoader.cacheLifetime(headers: ["cache-control": "max-age=60", "Age": "25"]) == 35)
        #expect(MapTileLoader.cacheLifetime(headers: ["cache-control": "max-age=10", "age": "25"]) == 0)
        for value in ["no-store", "public, no-cache", "no-cache=\"field\"", "max-age=garbage", "max-age=-1"] {
            #expect(MapTileLoader.cacheLifetime(headers: ["cache-control": value]) == nil)
        }
        #expect(MapTileLoader.cacheLifetime(headers: ["age": "garbage"]) == nil)
    }

    @Test("Cache eviction bounds both sixty-four addresses and thirty-two MiB")
    func cacheBounds() async throws {
        // Empty tiles still consume address slots. Widely separated cameras
        // exercise eviction without relying on source-feature truncation.
        let loader = MapTileLoader(source: try source(range: 10...10), transport: { _, _ in
            .init(data: Data(), headers: [:])
        })
        for index in 0..<40 {
            _ = try await loader.load(request(longitude: Double(index) * 8 - 160, span: 0.5))
            let statistics = await loader.statistics()
            #expect(statistics.cacheEntries <= 64 && statistics.cacheBytes <= 32 * 1_024 * 1_024)
        }
        #expect(await loader.statistics().cacheEntries == 64)
        // Valid MVT unknown length-delimited fields are retained only as raw
        // bytes; each tile decodes to an empty canonical dataset.
        let padded = paddingTile(bytes: 12 * 1_024 * 1_024)
        let byteLoader = MapTileLoader(source: try source(range: 10...10), transport: { _, _ in
            .init(data: padded, headers: [:])
        })
        _ = try await byteLoader.load(request(span: 0.5))
        let statistics = await byteLoader.statistics()
        #expect(statistics.cacheBytes <= 32 * 1_024 * 1_024)
        #expect(statistics.cacheEntries == 2)
    }

    @Test("Budget exhaustion attempts at most three source zooms and reports attained resolution")
    func boundedFallback() async throws {
        let attempts = Mutex<[Int]>([])
        let request = try request(span: 0.03)
        let wanted = MapTilePlan.desiredZoom(for: request, range: 3...14)
        let loader = MapTileLoader(source: try source(), transport: { url, _ in
            let zoom = Int(url.pathComponents[2])!
            attempts.withLock { $0.append(zoom) }
            if zoom == wanted { throw MapTileLoader.LoadingError.responseTooLarge }
            return .init(data: Data(), headers: [:])
        })
        let snapshot = try await loader.load(request)
        #expect(snapshot.requestedZoom == wanted)
        #expect(snapshot.attainedZoom == wanted - 1)
        #expect(Set(attempts.withLock { $0 }) == [wanted, wanted - 1])
        let exhausted = Mutex<Set<Int>>([])
        let failed = MapTileLoader(source: try source(), transport: { url, _ in
            _ = exhausted.withLock { $0.insert(Int(url.pathComponents[2])!) }
            throw MapTileLoader.LoadingError.responseTooLarge
        })
        await #expect(throws: MapTileLoader.LoadingError.responseTooLarge) { try await failed.load(request) }
        #expect(exhausted.withLock { $0 } == Set((wanted - 2)...wanted))
    }

    @Test("Malformed geometry and HTTP failures reject the whole plan without zoom retry")
    func failuresDoNotMasqueradeAsEmptyMaps() async throws {
        for mode in 0..<2 {
            let zooms = Mutex<Set<Int>>([])
            let loader = MapTileLoader(source: try source(), transport: { url, _ in
                _ = zooms.withLock { $0.insert(Int(url.pathComponents[2])!) }
                if mode == 0 { throw MapTileLoader.LoadingError.httpStatus(503) }
                return .init(data: Data([0xff]), headers: [:])
            })
            do { _ = try await loader.load(request()); Issue.record("Incomplete/invalid plan succeeded") }
            catch {
                if mode == 0 { #expect(error as? MapTileLoader.LoadingError == .httpStatus(503)) }
                else { #expect(error as? OpenMapTilesAdapter.ValidationError == .malformedWire) }
            }
            #expect(zooms.withLock { $0.count } == 1)
        }
        let calls = Mutex(0)
        let wide = MapTileLoader(source: try source(), transport: { _, _ in
            calls.withLock { $0 += 1 }; return .init(data: Data(), headers: [:])
        })
        await #expect(throws: MapTileLoader.LoadingError.unsupportedViewport) {
            try await wide.load(request(span: 360))
        }
        #expect(calls.withLock { $0 } == 0)
    }

    @Test("Rapid replacements drain old children and never admit more than two HTTP operations")
    func replacementCancellation() async throws {
        let gate = TransportGate()
        let loader = MapTileLoader(source: try source(), transport: { url, _ in try await gate.fetch(url) })
        let firstRequest = try request(longitude: 0)
        let first = Task { try await loader.load(firstRequest) }
        defer { first.cancel() }
        try await bounded { try await gate.waitForFirstPair() }
        let secondRequest = try request(longitude: 80)
        let second = Task { try await loader.load(secondRequest) }
        defer { second.cancel() }
        let snapshot = try await bounded { try await second.value }
        #expect(snapshot.request == secondRequest)
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(await gate.maximumActive == 2)
        #expect(await loader.statistics().maximumInFlight == 2)
        #expect(await loader.statistics().inFlight == 0)
    }

    @Test("A third replacement supersedes a second request still waiting for cancellation acknowledgment")
    func tripleReplacementDrainsAcknowledgment() async throws {
        let gate = AcknowledgmentGate()
        let observed = Mutex<Set<String>>([])
        let loader = MapTileLoader(source: try source(), transport: { url, _ in
            try await gate.fetch(url, stage: ReplacementStage.name)
        }, now: {
            let stage = ReplacementStage.name
            if !stage.isEmpty, observed.withLock({ $0.insert(stage).inserted }) {
                Task { await gate.observeEntry(stage) }
            }
            return 0
        })
        let firstRequest = try request(longitude: 0)
        let secondRequest = try request(longitude: 80)
        let thirdRequest = try request(longitude: -80)
        let first = Task {
            try await ReplacementStage.$name.withValue("A") { try await loader.load(firstRequest) }
        }
        var second: Task<MapTileSnapshot, any Error>?
        var third: Task<MapTileSnapshot, any Error>?
        defer {
            first.cancel(); second?.cancel(); third?.cancel()
            // A deliberately retains its cancelled resources. Failure paths must
            // also release that fixture ownership before test teardown.
            Task { await gate.releaseAcknowledgment() }
        }
        try await bounded { try await gate.wait(for: .firstPair) }
        let replacement = Task {
            try await ReplacementStage.$name.withValue("B") { try await loader.load(secondRequest) }
        }
        second = replacement
        try await bounded { try await gate.wait(for: .entered("B")) }
        try await bounded { try await gate.wait(for: .cancelledPair) }
        // B caused cancellation, but A's two transfers still own admission.
        #expect(await gate.active == 2)
        #expect(await gate.stages == ["A", "A"])
        let newest = Task {
            try await ReplacementStage.$name.withValue("C") { try await loader.load(thirdRequest) }
        }
        third = newest
        try await bounded { try await gate.wait(for: .entered("C")) }
        // The clock observation occurs synchronously within load. Entering the
        // loader actor afterward proves C has reached its predecessor wait.
        let waiting = await loader.statistics()
        #expect(waiting.inFlight == 2)
        #expect(await gate.stages == ["A", "A"])
        await gate.releaseAcknowledgment()
        let snapshot = try await bounded { try await newest.value }
        #expect(snapshot.request == thirdRequest)
        await #expect(throws: CancellationError.self) { try await bounded { try await first.value } }
        await #expect(throws: CancellationError.self) { try await bounded { try await replacement.value } }
        let thirdPlan = try MapTilePlan(request: thirdRequest, zoom: snapshot.attainedZoom)
        let stages = await gate.stages
        #expect(stages.filter { $0 == "B" }.isEmpty)
        #expect(stages.filter { $0 == "C" }.count == thirdPlan.tiles.count)
        #expect(await gate.maximumActive == 2)
        #expect(await gate.active == 0)
        #expect(await loader.statistics().maximumInFlight == 2)
        #expect(await loader.statistics().inFlight == 0)
    }

    @Test("Injected deadline cancels children and rejects publication")
    func deadline() async throws {
        let gate = TransportGate()
        let loader = MapTileLoader(source: try source(), transport: { url, _ in try await gate.fetch(url) },
                                   sleep: { _ in try await gate.waitForFirstPair() })
        await #expect(throws: MapTileLoader.LoadingError.deadlineExceeded) {
            try await bounded { try await loader.load(request()) }
        }
        #expect(await loader.statistics().inFlight == 0)
    }

    private func source(range: ClosedRange<Int> = 0...14) throws -> OpenMapTilesSource {
        try .init(template: "https://example.test/tiles/{z}/{x}/{y}.pbf", zoomRange: range,
                  metadata: MapSourceMetadata(attribution: "Fixture", license: "Fixture",
                                              licenseURL: URL(string: "https://example.test/license")!,
                                              sourceURL: URL(string: "https://example.test")!, sourceRevision: "fixture"))
    }
    private func request(longitude: Double = 0, span: Double = 5) throws -> MapTileRequest {
        try .init(camera: MapCamera(center: MapCoordinate(latitude: 0, longitude: longitude), longitudeSpan: span),
                  viewport: MapViewport(columns: 96, rows: 32))
    }
    /// Put every tile's lines beside the shared world origin, inside the tiny
    /// requested viewport. Offscreen lines must not establish aggregate admission.
    private func visibleTransportationTile(url: URL, features: Int) -> Data {
        let zoom = Int(url.pathComponents[2])!
        let x = Int(url.pathComponents[3])!
        let y = Int(url.deletingPathExtension().lastPathComponent)!
        return transportationTile(features: features, x: x < (1 << zoom) / 2 ? 4_095 : 0,
                                  y: y < (1 << zoom) / 2 ? 4_095 : 0)
    }

    private func transportationTile(features: Int, x: Int, y: Int) -> Data {
        func varint(_ number: Int) -> [UInt8] {
            var number = number, output: [UInt8] = []
            while number >= 128 { output.append(UInt8(number & 127) | 128); number >>= 7 }
            output.append(UInt8(number)); return output
        }
        func message(_ field: Int, _ body: [UInt8]) -> [UInt8] {
            varint(field << 3 | 2) + varint(body.count) + body
        }
        let geometry = [UInt8(9)] + varint(x * 2) + varint(y * 2) + [10,2,2]
        let line: [UInt8] = [0x12,2,0,0,0x18,2] + message(4, geometry)
        let body = message(1, Array("transportation".utf8)) + [0x78,2,0x28,0x80,0x20]
            + message(3, Array("class".utf8)) + message(4, message(1, Array("primary".utf8)))
            + Array(repeating: message(2, line), count: features).flatMap { $0 }
        return Data(message(3, body))
    }
    private func paddingTile(bytes: Int) -> Data {
        var length = UInt64(bytes), result = Data([0x0a])
        while length >= 128 { result.append(UInt8(length & 127) | 128); length >>= 7 }
        result.append(UInt8(length)); result.append(Data(repeating: 0, count: bytes))
        return result
    }
    private func bounded<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask(operation: operation)
            group.addTask { try await Task.sleep(for: .seconds(5)); throw Timeout.expired }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
    private enum Timeout: Error { case expired }

    private enum ReplacementStage {
        @TaskLocal static var name = ""
    }

    /// Test transport separates observing cancellation from acknowledging cleanup.
    /// Event waits are cancellable; only the deliberately held cleanup requires
    /// explicit release, including the test's failure-path defer.
    private actor AcknowledgmentGate {
        enum Event: Hashable, Sendable { case firstPair, cancelledPair, entered(String) }
        var active = 0
        var maximumActive = 0
        var stages: [String] = []
        private var cancelled = 0
        private var released = false
        private var events: Set<Event> = []
        private var waiters: [Event: [UUID: CheckedContinuation<Void, any Error>]] = [:]
        private var cleanupWaiters: [CheckedContinuation<Void, Never>] = []

        func observeEntry(_ stage: String) { signal(.entered(stage)) }
        func wait(for event: Event) async throws {
            try Task.checkCancellation()
            if events.contains(event) { return }
            let id = UUID()
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await withCheckedThrowingContinuation { waiters[event, default: [:]][id] = $0 }
            } onCancel: { Task { await self.cancelWaiter(id, event: event) } }
        }
        private func cancelWaiter(_ id: UUID, event: Event) {
            waiters[event]?.removeValue(forKey: id)?.resume(throwing: CancellationError())
        }
        private func signal(_ event: Event) {
            events.insert(event)
            for waiter in (waiters.removeValue(forKey: event) ?? [:]).values { waiter.resume() }
        }
        func releaseAcknowledgment() {
            released = true
            let waiting = cleanupWaiters; cleanupWaiters = []
            for waiter in waiting { waiter.resume() }
        }
        func fetch(_ url: URL, stage: String) async throws -> MapHTTPClient.Response {
            stages.append(stage); active += 1; maximumActive = max(maximumActive, active)
            defer { active -= 1 }
            if stage == "A" {
                if stages.filter({ $0 == "A" }).count == 2 { signal(.firstPair) }
                do { try await Task.sleep(for: .seconds(4)) }
                catch {
                    cancelled += 1
                    if cancelled == 2 { signal(.cancelledPair) }
                    if !released { await withCheckedContinuation { cleanupWaiters.append($0) } }
                    throw error
                }
            }
            try Task.checkCancellation()
            return .init(data: Data(), headers: [:])
        }
    }

    private actor TransportGate {
        var active = 0
        var maximumActive = 0
        var calls = 0
        var pairWaiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
        func waitForFirstPair() async throws {
            try Task.checkCancellation()
            if calls >= 2 { return }
            let id = UUID()
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await withCheckedThrowingContinuation { pairWaiters[id] = $0 }
            } onCancel: {
                Task { await self.cancelWaiter(id) }
            }
        }
        private func cancelWaiter(_ id: UUID) {
            pairWaiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
        }
        func fetch(_ url: URL) async throws -> MapHTTPClient.Response {
            calls += 1; active += 1; maximumActive = max(maximumActive, active)
            defer { active -= 1 }
            let blocked = calls <= 2
            if calls == 2 { let waiting = pairWaiters; pairWaiters = [:]; for waiter in waiting.values { waiter.resume() } }
            if blocked { try await Task.sleep(for: .seconds(4)) }
            try Task.checkCancellation()
            return .init(data: Data(), headers: [:])
        }
    }
}
