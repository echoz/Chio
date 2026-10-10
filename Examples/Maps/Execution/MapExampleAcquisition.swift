import Chio
import Foundation

/// Offline is the default. A configured endpoint avoids provider discovery.
enum MapExampleAcquisition {
    case offline
    case openFreeMap
    case configured(OpenMapTilesSource)
    case cached(MapTileLoader)
    case pack(MapTileLoader)

    var usesTiles: Bool {
        switch self {
        case .offline: false
        case .openFreeMap, .configured, .cached, .pack: true
        }
    }

    var title: String {
        switch self {
        case .offline: "Offline"
        case .openFreeMap, .configured, .cached: "Online"
        case .pack: "Offline pack"
        }
    }

    var isOnline: Bool {
        switch self {
        case .offline, .pack: false
        case .openFreeMap, .configured, .cached: true
        }
    }

    func makeLoader() async throws -> MapTileLoader {
        switch self {
        case .offline: throw MapTileLoader.LoadingError.unsupportedViewport
        case .openFreeMap: return MapTileLoader(source: try await .fetchOpenFreeMap())
        case .configured(let source): return MapTileLoader(source: source)
        case .cached(let loader), .pack(let loader): return loader
        }
    }

    func openCache(directory: URL) async throws -> MapTileCache {
        let source: OpenMapTilesSource
        switch self {
        case .offline, .cached, .pack: throw MapTileCache.CacheError.invalidConfiguration
        case .openFreeMap: source = try await OpenMapTilesSource.fetchOpenFreeMap()
        case .configured(let configured): source = configured
        }
        return try MapTileCache.open(directory: directory, source: source)
    }

    static func configured(file: String) throws -> Self {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: file))
        defer { try? handle.close() }
        let bytes = try handle.read(upToCount: 16 * 1_024 + 1) ?? Data()
        guard bytes.count <= 16 * 1_024 else { throw MapValidationError.invalidTileSource }
        return try .configured(JSONDecoder().decode(OpenMapTilesSource.self, from: bytes))
    }
}

extension MapExampleAcquisition: Sendable {}
