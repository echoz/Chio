import Chio
import Foundation

/// Offline is the default. A configured endpoint avoids provider discovery.
enum MapExampleAcquisition {
    case offline
    case openFreeMap
    case configured(OpenMapTilesSource)

    var isOnline: Bool {
        switch self {
        case .offline: false
        case .openFreeMap, .configured: true
        }
    }

    func makeLoader() async throws -> MapTileLoader {
        switch self {
        case .offline: throw MapTileLoader.LoadingError.unsupportedViewport
        case .openFreeMap: return MapTileLoader(source: try await .fetchOpenFreeMap())
        case .configured(let source): return MapTileLoader(source: source)
        }
    }

    static func configured(file: String) throws -> Self {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: file))
        defer { try? handle.close() }
        let bytes = try handle.read(upToCount: 16 * 1_024 + 1) ?? Data()
        guard bytes.count <= 16 * 1_024 else { throw MapValidationError.invalidTileSource }
        return try .configured(JSONDecoder().decode(OpenMapTilesSource.self, from: bytes))
    }
}

extension MapExampleAcquisition: Hashable {}
extension MapExampleAcquisition: Sendable {}
