import Foundation

/// Version 1: header, contiguous raw tiles, JSON manifest, fixed-width index.
/// CRC32 covers the header/manifest/index and each payload; it is not authentication.
enum MapTilePackFormat {
    static let headerBytes = 40
    static let entryBytes = 32
    static let maximumManifestBytes = 16 * 1_024
    static let maximumPayloadBytes = 16 * 1_024 * 1_024
    private static let magic = Data("CHIOPACK".utf8)

    struct Manifest: Codable {
        let plan: MapTilePackPlan
        let metadata: MapSourceMetadata
    }

    struct Entry {
        let tile: MapTileCoordinate
        let offset: Int
        let length: Int
        let checksum: UInt32
    }

    struct Header {
        let manifestBytes: Int
        let entryCount: Int
        let rawBytes: Int
        let checksum: UInt32
        var indexBytes: Int { entryCount * entryBytes }
        var fileBytes: Int { headerBytes + rawBytes + manifestBytes + indexBytes }
    }

    static func manifest(plan: MapTilePackPlan, metadata: MapSourceMetadata) throws -> Data {
        // URLs have no domain length limit. Bound their strings before JSON escaping.
        let strings = [metadata.attribution, metadata.license, metadata.sourceRevision,
                       metadata.licenseURL.absoluteString, metadata.sourceURL.absoluteString]
            + [metadata.attributionURL?.absoluteString].compactMap { $0 }
        var textBytes = 0
        for string in strings {
            textBytes += string.utf8.prefix(maximumManifestBytes + 1).count
            guard textBytes <= maximumManifestBytes else { throw MapTilePack.PackError.invalidConfiguration }
        }
        let data = try JSONEncoder().encode(Manifest(plan: plan, metadata: metadata))
        guard data.count <= maximumManifestBytes else { throw MapTilePack.PackError.invalidConfiguration }
        return data
    }

    static func index(_ entries: [Entry]) -> Data {
        var data = Data()
        data.reserveCapacity(entries.count * entryBytes)
        for entry in entries {
            for component in [entry.tile.zoom, entry.tile.x, entry.tile.y] {
                append(UInt64(component), bytes: 4, to: &data)
            }
            append(UInt64(entry.offset), bytes: 8, to: &data)
            append(UInt64(entry.length), bytes: 4, to: &data)
            append(UInt64(entry.checksum), bytes: 4, to: &data)
            append(0, bytes: 4, to: &data)
        }
        return data
    }

    static func header(manifest: Data, index: Data, count: Int, rawBytes: Int) throws -> Data {
        var data = magic
        append(1, bytes: 4, to: &data)
        append(UInt64(manifest.count), bytes: 4, to: &data)
        append(UInt64(count), bytes: 4, to: &data)
        append(UInt64(index.count), bytes: 4, to: &data)
        append(UInt64(rawBytes), bytes: 8, to: &data)
        let checksum = try MapTileChecksum.crc32(data + manifest + index)
        append(UInt64(checksum), bytes: 4, to: &data)
        append(0, bytes: 4, to: &data)
        return data
    }

    static func decodeHeader(_ data: Data) throws -> Header {
        guard data.count == headerBytes, data.prefix(8) == magic else { throw MapTilePack.PackError.corruptPack }
        guard integer(data, offset: 8, bytes: 4) == 1 else { throw MapTilePack.PackError.unsupportedFormat }
        let manifestBytes = integer(data, offset: 12, bytes: 4)
        let count = integer(data, offset: 16, bytes: 4)
        let indexBytes = integer(data, offset: 20, bytes: 4)
        let rawBytes = integer(data, offset: 24, bytes: 8)
        let hasBoundedManifest = (1...UInt64(maximumManifestBytes)).contains(manifestBytes)
        let hasBoundedCount = (1...UInt64(MapTilePackPlan.maximumTiles)).contains(count)
        let hasBoundedPayload = rawBytes <= UInt64(MapTilePackPlan.hardMaximumBytes)
        guard hasBoundedManifest, hasBoundedCount, hasBoundedPayload else { throw MapTilePack.PackError.corruptPack }
        let hasExactIndexLength = indexBytes == count * UInt64(entryBytes)
        let hasZeroReservedWord = integer(data, offset: 36, bytes: 4) == 0
        guard hasExactIndexLength, hasZeroReservedWord else { throw MapTilePack.PackError.corruptPack }
        return Header(manifestBytes: Int(manifestBytes), entryCount: Int(count), rawBytes: Int(rawBytes),
                      checksum: UInt32(integer(data, offset: 32, bytes: 4)))
    }

    static func decode(header: Data, manifest: Data, index: Data) throws -> (Manifest, [Entry]) {
        let framing = try decodeHeader(header)
        let hasExactManifestLength = manifest.count == framing.manifestBytes
        let hasExactIndexLength = index.count == framing.indexBytes
        guard hasExactManifestLength, hasExactIndexLength else { throw MapTilePack.PackError.corruptPack }
        let observedChecksum = try MapTileChecksum.crc32(Data(header.prefix(32)) + manifest + index)
        guard observedChecksum == framing.checksum else { throw MapTilePack.PackError.corruptPack }
        let decoded: Manifest
        do { decoded = try JSONDecoder().decode(Manifest.self, from: manifest) }
        catch { throw MapTilePack.PackError.corruptPack }
        let hasExactTileCount = decoded.plan.tiles.count == framing.entryCount
        let hasSupportedByteTotal = framing.rawBytes <= decoded.plan.maximumBytes
        guard hasExactTileCount, hasSupportedByteTotal else { throw MapTilePack.PackError.corruptPack }
        var entries: [Entry] = []
        var nextOffset = 0
        for (position, tile) in decoded.plan.tiles.enumerated() {
            let base = position * entryBytes
            let hasExpectedZoom = integer(index, offset: base, bytes: 4) == UInt64(tile.zoom)
            let hasExpectedX = integer(index, offset: base + 4, bytes: 4) == UInt64(tile.x)
            let hasExpectedY = integer(index, offset: base + 8, bytes: 4) == UInt64(tile.y)
            let hasZeroReservedWord = integer(index, offset: base + 28, bytes: 4) == 0
            guard hasExpectedZoom, hasExpectedX, hasExpectedY, hasZeroReservedWord else {
                throw MapTilePack.PackError.corruptPack
            }
            let offset = integer(index, offset: base + 12, bytes: 8)
            let length = integer(index, offset: base + 20, bytes: 4)
            let hasContiguousOffset = offset == UInt64(nextOffset)
            let hasBoundedLength = length <= UInt64(maximumPayloadBytes)
            guard hasContiguousOffset, hasBoundedLength else { throw MapTilePack.PackError.corruptPack }
            guard Int(length) <= framing.rawBytes - nextOffset else { throw MapTilePack.PackError.corruptPack }
            entries.append(Entry(tile: tile, offset: nextOffset, length: Int(length),
                                 checksum: UInt32(integer(index, offset: base + 24, bytes: 4))))
            nextOffset += Int(length)
        }
        guard nextOffset == framing.rawBytes else { throw MapTilePack.PackError.corruptPack }
        return (decoded, entries)
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
