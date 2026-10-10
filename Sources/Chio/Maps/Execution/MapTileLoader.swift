import Foundation

/// Explicit tile acquisition for one mounted map consumer. A replacement load
/// cancels and drains its predecessor before starting at most two tile reads.
public actor MapTileLoader {
    public enum LoadingError {
        case unsupportedViewport, outsidePackCoverage, deadlineExceeded, invalidCatalog
        case invalidResponse, httpStatus(Int), unexpectedContentType, responseTooLarge, rejectedRedirect
    }

    private enum Backing {
        case online(OpenMapTilesSource, MapTileCache?, MapHTTPClient.Transport)
        case pack(MapTilePack)
    }

    private enum Retention {
        case online(expires: TimeInterval, storedAt: TimeInterval, expiresAt: TimeInterval)
        case pack
    }

    private struct CachedTile {
        let data: Data
        let retention: Retention
        let access: UInt64
    }
    struct Statistics {
        let cacheEntries: Int
        let cacheBytes: Int
        let inFlight: Int
        let maximumInFlight: Int
    }

    private let backing: Backing
    private var metadata: MapSourceMetadata {
        switch backing {
        case .online(let source, _, _): source.metadata
        case .pack(let pack): pack.metadata
        }
    }
    private var zoomRange: ClosedRange<Int> {
        switch backing {
        case .online(let source, _, _): source.zoomRange
        case .pack(let pack): pack.plan.zoomRange
        }
    }
    private var diskCache: MapTileCache? {
        switch backing {
        case .online(_, let cache, _): cache
        case .pack: nil
        }
    }
    private let now: @Sendable () -> TimeInterval
    private let wallNow: @Sendable () -> TimeInterval
    private let sleep: @Sendable (Duration) async throws -> Void
    private var active: Task<MapTileSnapshot, any Error>?
    private var generation: UInt64 = 0
    private var cache: [MapTileCoordinate: CachedTile] = [:]
    private var cacheBytes = 0
    private var access: UInt64 = 0
    private var freshnessClock: (effective: TimeInterval, uptime: TimeInterval)?
    private var inFlight = 0
    private var maximumInFlight = 0

    public init(source: OpenMapTilesSource) {
        self.backing = .online(source, nil, { try await MapHTTPClient.fetch($0, resource: $1) })
        self.now = { ProcessInfo.processInfo.systemUptime }
        self.wallNow = { Date().timeIntervalSince1970 }
        self.sleep = { try await Task.sleep(for: $0) }
    }

    /// Reuse fresh raw tiles across launches using an explicitly opened cache.
    /// The cache owns its source and must remain open while this loader is used.
    /// Storage failures propagate; closing the cache also disables memory hits.
    public init(cache: MapTileCache) {
        self.backing = .online(cache.source, cache, { try await MapHTTPClient.fetch($0, resource: $1) })
        self.now = { ProcessInfo.processInfo.systemUptime }
        self.wallNow = { Date().timeIntervalSince1970 }
        self.sleep = { try await Task.sleep(for: $0) }
    }

    /// Internal effect injection keeps deterministic tests out of the public API.
    init(source: OpenMapTilesSource, transport: @escaping MapHTTPClient.Transport,
         now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.backing = .online(source, nil, transport)
        self.now = now; self.sleep = sleep
        self.wallNow = { Date().timeIntervalSince1970 }
    }

    init(cache: MapTileCache, transport: @escaping MapHTTPClient.Transport,
         now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         wallNow: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 },
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.backing = .online(cache.source, cache, transport)
        self.now = now; self.wallNow = wallNow; self.sleep = sleep
    }

    /// Read immutable pack tiles without discovery, HTTP or writable disk caching.
    /// Retain the reader until this consumer stops; closing it also disables memory hits.
    public init(pack: MapTilePack) {
        self.backing = .pack(pack)
        self.now = { ProcessInfo.processInfo.systemUptime }
        self.wallNow = { Date().timeIntervalSince1970 }
        self.sleep = { try await Task.sleep(for: $0) }
    }

    /// Only the deadline clock is used by pack loading; UTC must not affect retention.
    init(pack: MapTilePack, now: @escaping @Sendable () -> TimeInterval,
         wallNow: @escaping @Sendable () -> TimeInterval) {
        self.backing = .pack(pack)
        self.now = now; self.wallNow = wallNow
        self.sleep = { try await Task.sleep(for: $0) }
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
        try await ensureBackingOpen()
        try Task.checkCancellation()
        guard owner == generation else { throw CancellationError() }
        return result
    }

    func statistics() -> Statistics {
        expireCache()
        return Statistics(cacheEntries: cache.count, cacheBytes: cacheBytes,
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
        let floor = max(1, zoomRange.lowerBound)
        guard floor <= zoomRange.upperBound else { throw LoadingError.unsupportedViewport }
        let requested = MapTilePlan.desiredZoom(for: request, range: floor...zoomRange.upperBound)
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
                    let decoded = try OpenMapTilesAdapter(tile: tile, metadata: metadata)
                        .adapt(data, intersecting: request)
                    try Task.checkCancellation()
                    vertices += decoded.vertexCount
                    guard features.count + decoded.features.count <= MapLimits.features,
                          vertices <= MapLimits.sourceVertices else { throw MapValidationError.budgetExceeded }
                    features.append(contentsOf: decoded.features)
                }
                let coverage = try MapTileCoverage(tiles: plan.tiles, region: request)
                let aggregate = try MapSource(dataset: MapDataset(features: features), metadata: metadata,
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
            if let error = lastBudgetError as? MapValidationError {
                switch error {
                case .tileLimitExceeded: throw LoadingError.unsupportedViewport
                case .invalidCoordinate, .invalidCamera, .invalidViewport, .invalidIdentity,
                     .invalidPath, .invalidRing, .duplicateIdentity, .unsupportedGeoJSON,
                     .budgetExceeded, .drawingBudgetExceeded, .invalidTileSource,
                     .invalidTileCoverage, .invalidTileSnapshot: break
                }
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

    private func ensureBackingOpen() async throws {
        switch backing {
        case .online(_, let cache, _): try await cache?.ensureOpen()
        case .pack(let pack): try await pack.ensureOpen()
        }
    }

    private func bytes(for tile: MapTileCoordinate) async throws -> Data {
        try Task.checkCancellation()
        try await ensureBackingOpen()
        try Task.checkCancellation()
        expireCache()
        access &+= 1
        if let cached = cache[tile] {
            cache[tile] = CachedTile(data: cached.data, retention: cached.retention, access: access)
            return cached.data
        }
        switch backing {
        case .pack(let pack):
            guard let data = try await pack.read(tile) else { throw LoadingError.outsidePackCoverage }
            try Task.checkCancellation()
            try await pack.ensureOpen()
            try Task.checkCancellation()
            insert(data, tile: tile, retention: .pack)
            return data
        case .online(let source, _, let transport):
            return try await onlineBytes(for: tile, source: source, transport: transport)
        }
    }

    private func onlineBytes(for tile: MapTileCoordinate, source: OpenMapTilesSource,
                             transport: MapHTTPClient.Transport) async throws -> Data {
        let lookup = cacheTime()
        if let diskCache, let entry = try await diskCache.read(tile, at: lookup.effective) {
            try Task.checkCancellation()
            let expires = lookup.uptime + (entry.expiresAt - lookup.effective)
            let completed = cacheTime()
            let hasValidReceipt = completed.wall.isFinite && completed.wall >= entry.storedAt
            let isStillFresh = completed.uptime < expires && completed.effective < entry.expiresAt
            if hasValidReceipt && isStillFresh {
                insert(entry.data, tile: tile, retention: .online(expires: expires,
                       storedAt: entry.storedAt, expiresAt: entry.expiresAt))
                return entry.data
            }
            try await diskCache.remove(tile)
        }
        try Task.checkCancellation()
        let url = try source.url(for: tile)
        inFlight += 1
        maximumInFlight = max(maximumInFlight, inFlight)
        defer { inFlight -= 1 }
        let response = try await transport(url, .tile)
        try Task.checkCancellation()
        let received = now()
        let receivedAt = wallNow()
        try await diskCache?.ensureOpen()
        try Task.checkCancellation()
        // Injected transports must preserve the production byte admission contract.
        guard response.data.count <= MapHTTPClient.Resource.tile.limit else { throw LoadingError.responseTooLarge }
        if let ttl = Self.cacheLifetime(headers: response.headers), ttl > 0 {
            let expiresAt = receivedAt + ttl
            if let diskCache {
                // A fractional HTTP lifetime may be below UTC's representable
                // precision. The response remains usable without disk retention.
                if expiresAt == receivedAt {
                    try await diskCache.remove(tile)
                    try Task.checkCancellation()
                    return response.data
                }
                try await diskCache.store(response.data, for: tile, storedAt: receivedAt, expiresAt: expiresAt)
            }
            try Task.checkCancellation()
            insert(response.data, tile: tile, retention: .online(expires: received + ttl,
                   storedAt: receivedAt, expiresAt: expiresAt))
        } else {
            try await diskCache?.remove(tile)
        }
        try Task.checkCancellation()
        return response.data
    }

    private func expireCache() {
        switch backing {
        case .pack: return
        case .online: break
        }
        let time = cacheTime()
        let expired = cache.filter { _, tile in
            switch tile.retention {
            case .pack: return false
            case .online(let expires, let storedAt, let expiresAt):
                let hasExpiredUptime = expires <= time.uptime
                let hasInvalidWallTime = !time.wall.isFinite || time.wall < storedAt || time.effective >= expiresAt
                return hasExpiredUptime || (diskCache != nil && hasInvalidWallTime)
            }
        }.map(\.key)
        for tile in expired { cacheBytes -= cache.removeValue(forKey: tile)!.data.count }
    }

    /// A loader-session floor keeps a stalled/backward UTC clock from renewing
    /// disk freshness after memory eviction. Persisted receipt times remain UTC.
    private func cacheTime() -> (wall: TimeInterval, effective: TimeInterval, uptime: TimeInterval) {
        let wall = wallNow()
        let uptime = now()
        guard wall.isFinite, uptime.isFinite else { return (wall, wall, uptime) }
        let effective: TimeInterval
        if let freshnessClock {
            let elapsed = max(0, uptime - freshnessClock.uptime)
            effective = max(wall, freshnessClock.effective + elapsed)
        } else { effective = wall }
        freshnessClock = (effective, uptime)
        return (wall, effective, uptime)
    }

    private func insert(_ data: Data, tile: MapTileCoordinate, retention: Retention) {
        expireCache()
        if let prior = cache.removeValue(forKey: tile) { cacheBytes -= prior.data.count }
        while cache.count >= 64 || cacheBytes + data.count > 32 * 1_024 * 1_024 {
            guard let oldest = cache.min(by: { $0.value.access < $1.value.access })?.key else { break }
            cacheBytes -= cache.removeValue(forKey: oldest)!.data.count
        }
        access &+= 1
        cache[tile] = CachedTile(data: data, retention: retention, access: access)
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
