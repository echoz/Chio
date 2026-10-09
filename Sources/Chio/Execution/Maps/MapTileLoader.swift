import Foundation

/// Explicit online acquisition for one mounted map consumer. A replacement load
/// cancels and drains its predecessor before starting at most two HTTP requests.
public actor MapTileLoader {
    public enum LoadingError {
        case unsupportedViewport, deadlineExceeded, invalidCatalog
        case invalidResponse, httpStatus(Int), unexpectedContentType, responseTooLarge, rejectedRedirect
    }

    private struct CachedTile {
        let data: Data
        let expires: TimeInterval
        let access: UInt64
    }
    struct Statistics {
        let cacheEntries: Int
        let cacheBytes: Int
        let inFlight: Int
        let maximumInFlight: Int
    }

    private let source: OpenMapTilesSource
    private let transport: MapHTTPClient.Transport
    private let now: @Sendable () -> TimeInterval
    private let sleep: @Sendable (Duration) async throws -> Void
    private var active: Task<MapTileSnapshot, any Error>?
    private var generation: UInt64 = 0
    private var cache: [MapTileCoordinate: CachedTile] = [:]
    private var cacheBytes = 0
    private var access: UInt64 = 0
    private var inFlight = 0
    private var maximumInFlight = 0

    public init(source: OpenMapTilesSource) {
        self.source = source
        self.transport = { try await MapHTTPClient.fetch($0, resource: $1) }
        self.now = { ProcessInfo.processInfo.systemUptime }
        self.sleep = { try await Task.sleep(for: $0) }
    }

    /// Internal effect injection keeps deterministic tests out of the public API.
    init(source: OpenMapTilesSource, transport: @escaping MapHTTPClient.Transport,
         now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.source = source; self.transport = transport; self.now = now; self.sleep = sleep
    }

    public func load(_ request: MapTileRequest) async throws -> MapTileSnapshot {
        try Task.checkCancellation()
        generation &+= 1
        let owner = generation
        let started = now()
        let predecessor = active
        predecessor?.cancel()
        if let predecessor { _ = await predecessor.result }
        try Task.checkCancellation()
        guard owner == generation else { throw CancellationError() }
        let remaining = 30 - (now() - started)
        guard remaining > 0 else { throw LoadingError.deadlineExceeded }
        let operation = Task { try await self.withDeadline(request, seconds: remaining) }
        active = operation
        defer { if owner == generation { active = nil } }
        let result = try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: { operation.cancel() }
        try Task.checkCancellation()
        guard owner == generation else { throw CancellationError() }
        return result
    }

    func statistics() -> Statistics {
        expireCache()
        return .init(cacheEntries: cache.count, cacheBytes: cacheBytes,
                     inFlight: inFlight, maximumInFlight: maximumInFlight)
    }

    private func withDeadline(_ request: MapTileRequest, seconds: TimeInterval) async throws -> MapTileSnapshot {
        let sleep = self.sleep
        return try await withThrowingTaskGroup(of: MapTileSnapshot.self) { group in
            group.addTask { try await self.acquire(request) }
            group.addTask {
                try await sleep(.seconds(seconds))
                try Task.checkCancellation()
                throw LoadingError.deadlineExceeded
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            return result
        }
    }

    private func acquire(_ request: MapTileRequest) async throws -> MapTileSnapshot {
        let floor = max(1, source.zoomRange.lowerBound)
        guard floor <= source.zoomRange.upperBound else { throw LoadingError.unsupportedViewport }
        let requested = MapTilePlan.desiredZoom(for: request, range: floor...source.zoomRange.upperBound)
        var lastBudgetError: (any Error)?
        for zoom in stride(from: requested, through: max(floor, requested - 2), by: -1) {
            try Task.checkCancellation()
            do {
                let plan = try MapTilePlan(request: request, zoom: zoom)
                let tiles = try await fetch(plan.tiles)
                var features: [MapFeature] = []
                var vertices = 0
                for tile in plan.tiles {
                    try Task.checkCancellation()
                    guard let data = tiles[tile] else { throw LoadingError.invalidResponse }
                    let decoded = try OpenMapTilesAdapter(tile: tile, metadata: source.metadata)
                        .adapt(data, intersecting: request)
                    try Task.checkCancellation()
                    vertices += decoded.vertexCount
                    guard features.count + decoded.features.count <= MapLimits.features,
                          vertices <= MapLimits.sourceVertices else { throw MapValidationError.budgetExceeded }
                    features.append(contentsOf: decoded.features)
                }
                let coverage = try MapTileCoverage(tiles: plan.tiles, region: request)
                let aggregate = try MapSource(dataset: MapDataset(features: features), metadata: source.metadata,
                                              coverage: .tiled(coverage))
                try Task.checkCancellation()
                return try MapTileSnapshot(request: request, source: aggregate, requestedZoom: requested)
            } catch MapValidationError.tileLimitExceeded {
                lastBudgetError = MapValidationError.tileLimitExceeded
            } catch MapValidationError.budgetExceeded {
                lastBudgetError = MapValidationError.budgetExceeded
            } catch OpenMapTilesAdapter.ValidationError.budgetExceeded {
                lastBudgetError = OpenMapTilesAdapter.ValidationError.budgetExceeded
            } catch LoadingError.responseTooLarge {
                lastBudgetError = LoadingError.responseTooLarge
            }
        }
        if let lastBudgetError {
            if let error = lastBudgetError as? MapValidationError, error == .tileLimitExceeded {
                throw LoadingError.unsupportedViewport
            }
            throw lastBudgetError
        }
        throw LoadingError.unsupportedViewport
    }

    private func fetch(_ tiles: [MapTileCoordinate]) async throws -> [MapTileCoordinate: Data] {
        try await withThrowingTaskGroup(of: (MapTileCoordinate, Data).self) { group in
            var next = 0
            var loaded: [MapTileCoordinate: Data] = [:]
            func enqueue() {
                let tile = tiles[next]
                next += 1
                group.addTask { (tile, try await self.bytes(for: tile)) }
            }
            for _ in 0..<min(2, tiles.count) { enqueue() }
            defer { group.cancelAll() }
            while let (tile, data) = try await group.next() {
                try Task.checkCancellation()
                loaded[tile] = data
                if next < tiles.count { enqueue() }
            }
            return loaded
        }
    }

    private func bytes(for tile: MapTileCoordinate) async throws -> Data {
        try Task.checkCancellation()
        expireCache()
        access &+= 1
        if let cached = cache[tile] {
            cache[tile] = .init(data: cached.data, expires: cached.expires, access: access)
            return cached.data
        }
        let url = try source.url(for: tile)
        inFlight += 1
        maximumInFlight = max(maximumInFlight, inFlight)
        defer { inFlight -= 1 }
        let response = try await transport(url, .tile)
        try Task.checkCancellation()
        // Injected transports must preserve the production byte admission contract.
        guard response.data.count <= MapHTTPClient.Resource.tile.limit else { throw LoadingError.responseTooLarge }
        if let ttl = Self.cacheLifetime(headers: response.headers), ttl > 0 {
            insert(response.data, tile: tile, expires: now() + ttl)
        }
        return response.data
    }

    private func expireCache() {
        let expired = cache.filter { $0.value.expires <= now() }.map(\.key)
        for tile in expired { cacheBytes -= cache.removeValue(forKey: tile)!.data.count }
    }

    private func insert(_ data: Data, tile: MapTileCoordinate, expires: TimeInterval) {
        expireCache()
        if let prior = cache.removeValue(forKey: tile) { cacheBytes -= prior.data.count }
        while cache.count >= 64 || cacheBytes + data.count > 32 * 1_024 * 1_024 {
            guard let oldest = cache.min(by: { $0.value.access < $1.value.access })?.key else { break }
            cacheBytes -= cache.removeValue(forKey: oldest)!.data.count
        }
        access &+= 1
        cache[tile] = .init(data: data, expires: expires, access: access)
        cacheBytes += data.count
    }

    static func cacheLifetime(headers: [String: String]) -> TimeInterval? {
        let headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })
        let directives = (headers["cache-control"] ?? "").lowercased().split(separator: ",")
            .map { directive -> (String, String?) in
                let parts = directive.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let name = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts.count == 2 ? parts[1].trimmingCharacters(in: .whitespaces) : nil
                return (name, value)
            }
        if directives.contains(where: { ["no-store", "no-cache"].contains($0.0) }) { return nil }
        var lifetime: TimeInterval?
        for (name, text) in directives where name == "max-age" {
            guard let text, let value = TimeInterval(text.trimmingCharacters(in: CharacterSet(charactersIn: "\""))),
                  value.isFinite, value >= 0 else { return nil }
            lifetime = min(lifetime ?? value, value)
        }
        var age: TimeInterval = 0
        if let text = headers["age"] {
            guard let value = TimeInterval(text.trimmingCharacters(in: .whitespaces)), value.isFinite, value >= 0 else { return nil }
            age = value
        }
        // Bound retention after calculating remaining advertised freshness. An
        // old resource with a long max-age may still be fresh for thirty minutes.
        return min(1_800, max(0, (lifetime ?? 1_800) - age))
    }
}

extension MapTileLoader.LoadingError: Error {}
extension MapTileLoader.LoadingError: Equatable {}
extension MapTileLoader.LoadingError: Sendable {}
extension MapTileLoader.Statistics: Sendable {}
