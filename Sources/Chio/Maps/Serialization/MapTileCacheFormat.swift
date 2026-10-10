import Foundation

/// Versioned framing; checksum covers address, freshness, length and raw bytes.
/// CRC32 detects accidental corruption and makes no authenticity claim.
enum MapTileCacheFormat {
    static let maximumPayloadBytes = 16 * 1_024 * 1_024
    static let overheadBytes = 48
    static let maximumManifestBytes = 16 * 1_024
    private static let magic = Data("CHIOTILE".utf8)

    struct Manifest: Codable {
        let version: Int
        let source: OpenMapTilesSource
    }

    static func manifest(for source: OpenMapTilesSource) throws -> Data {
        // URL values have no size invariant in MapSourceMetadata. Bound each
        // persisted string and their aggregate before JSON escaping allocates output.
        let metadata = source.metadata
        let strings = [source.template, metadata.attribution, metadata.license, metadata.sourceRevision,
                       metadata.licenseURL.absoluteString, metadata.sourceURL.absoluteString]
            + [metadata.attributionURL?.absoluteString].compactMap { $0 }
        var textBytes = 0
        for string in strings {
            textBytes += string.utf8.prefix(maximumManifestBytes + 1).count
            guard textBytes <= maximumManifestBytes else { throw MapTileCache.CacheError.invalidConfiguration }
        }
        let data = try JSONEncoder().encode(Manifest(version: 1, source: source))
        guard data.count <= maximumManifestBytes else { throw MapTileCache.CacheError.invalidConfiguration }
        return data
    }

    static func validateManifest(_ data: Data, source: OpenMapTilesSource) throws {
        // Inspect the version independently so a future schema is distinguished
        // from an invalid source or malformed v1 manifest.
        struct Version: Decodable { let version: Int }
        let decoder = JSONDecoder()
        let version: Version
        do { version = try decoder.decode(Version.self, from: data) }
        catch { throw MapTileCache.CacheError.corruptManifest }
        guard version.version == 1 else { throw MapTileCache.CacheError.unsupportedFormat }
        let manifest: Manifest
        do { manifest = try decoder.decode(Manifest.self, from: data) }
        catch { throw MapTileCache.CacheError.corruptManifest }
        guard manifest.source == source else { throw MapTileCache.CacheError.sourceMismatch }
    }

    static func encode(_ entry: MapTileCache.Entry, tile: MapTileCoordinate) throws -> Data {
        guard entry.data.count <= maximumPayloadBytes else { throw MapTileCache.CacheError.invalidConfiguration }
        try validateTimes(storedAt: entry.storedAt, expiresAt: entry.expiresAt)
        var encoded = magic
        append(1, bytes: 4, to: &encoded)
        for component in [tile.zoom, tile.x, tile.y] { append(UInt64(component), bytes: 4, to: &encoded) }
        append(entry.storedAt.bitPattern, bytes: 8, to: &encoded)
        append(entry.expiresAt.bitPattern, bytes: 8, to: &encoded)
        append(UInt64(entry.data.count), bytes: 4, to: &encoded)
        encoded.append(entry.data)
        append(UInt64(try MapTileChecksum.crc32(encoded)), bytes: 4, to: &encoded)
        return encoded
    }

    static func decode(_ data: Data, tile: MapTileCoordinate) throws -> MapTileCache.Entry? {
        let hasBoundedSize = (overheadBytes...(maximumPayloadBytes + overheadBytes)).contains(data.count)
        guard hasBoundedSize else { return nil }
        guard data.prefix(8) == magic, integer(data, offset: 8, bytes: 4) == 1 else { return nil }
        let hasExpectedAddress = integer(data, offset: 12, bytes: 4) == UInt64(tile.zoom)
            && integer(data, offset: 16, bytes: 4) == UInt64(tile.x)
            && integer(data, offset: 20, bytes: 4) == UInt64(tile.y)
        guard hasExpectedAddress else { return nil }
        let storedAt = TimeInterval(bitPattern: integer(data, offset: 24, bytes: 8))
        let expiresAt = TimeInterval(bitPattern: integer(data, offset: 32, bytes: 8))
        do { try validateTimes(storedAt: storedAt, expiresAt: expiresAt) }
        catch { return nil }
        guard integer(data, offset: 40, bytes: 4) == UInt64(data.count - overheadBytes) else { return nil }
        let framed = Data(data.dropLast(4))
        guard integer(data, offset: data.count - 4, bytes: 4) == UInt64(try MapTileChecksum.crc32(framed)) else { return nil }
        return MapTileCache.Entry(data: Data(data[44..<(data.count - 4)]), storedAt: storedAt, expiresAt: expiresAt)
    }

    static func validateTimes(storedAt: TimeInterval, expiresAt: TimeInterval) throws {
        let hasFiniteTimes = storedAt.isFinite && expiresAt.isFinite
        let hasPositiveLifetime = expiresAt > storedAt
        let hasBoundedLifetime = expiresAt - storedAt <= 1_800
        guard hasFiniteTimes, hasPositiveLifetime, hasBoundedLifetime else {
            throw MapTileCache.CacheError.invalidConfiguration
        }
    }

    private static func append(_ number: UInt64, bytes: Int, to data: inout Data) {
        for index in 0..<bytes { data.append(UInt8(truncatingIfNeeded: number >> (index * 8))) }
    }

    private static func integer(_ data: Data, offset: Int, bytes: Int) -> UInt64 {
        var number: UInt64 = 0
        for index in 0..<bytes { number |= UInt64(data[offset + index]) << (index * 8) }
        return number
    }


}
