@testable import Chio
import Foundation
import Testing

struct MapTilePackFormatTests {
    @Test("Versioned framing preserves a complete plan and valid empty payloads")
    func roundTrip() throws {
        let plan = try plan()
        let manifest = try MapTilePackFormat.manifest(plan: plan, metadata: metadata())
        let entry = MapTilePackFormat.Entry(tile: plan.tiles[0], offset: 0, length: 0, checksum: 0)
        let index = MapTilePackFormat.index([entry])
        let header = try MapTilePackFormat.header(manifest: manifest, index: index, count: 1, rawBytes: 0)
        let (decoded, entries) = try MapTilePackFormat.decode(header: header, manifest: manifest, index: index)
        #expect(decoded.plan == plan)
        #expect(decoded.metadata == (try metadata()))
        #expect(entries.count == 1 && entries[0].length == 0)
        #expect(try MapTileChecksum.crc32(Data()) == 0)
        #expect(try MapTileChecksum.crc32(Data("123456789".utf8)) == 0xcbf43926)
    }

    @Test("Checksum-valid malformed indexes reject wrong, missing, duplicate and unbounded entries")
    func malformedIndex() throws {
        let plan = try plan()
        let manifest = try MapTilePackFormat.manifest(plan: plan, metadata: metadata())
        let entry = MapTilePackFormat.Entry(tile: plan.tiles[0], offset: 0, length: 1, checksum: 0)
        let original = MapTilePackFormat.index([entry])
        for offset in [0, 4, 8, 12, 20, 28] {
            var index = original
            index[offset] ^= 255
            let header = try MapTilePackFormat.header(manifest: manifest, index: index, count: 1, rawBytes: 1)
            #expect(throws: MapTilePack.PackError.corruptPack) {
                try MapTilePackFormat.decode(header: header, manifest: manifest, index: index)
            }
        }
        for index in [Data(), original + original, Data(original.dropLast())] {
            let header = try MapTilePackFormat.header(manifest: manifest, index: index, count: 1, rawBytes: 1)
            #expect(throws: MapTilePack.PackError.corruptPack) {
                try MapTilePackFormat.decode(header: header, manifest: manifest, index: index)
            }
        }
        let twoZoomPlan = try MapTilePackPlan(bounds: plan.bounds, zoomRange: 1...2, maximumBytes: 10)
        let largerManifest = try MapTilePackFormat.manifest(plan: twoZoomPlan, metadata: metadata())
        let firstEntry = MapTilePackFormat.Entry(tile: twoZoomPlan.tiles[0], offset: 0, length: 0, checksum: 0)
        // Both envelopes are internally length-consistent and checksum-valid.
        // The first omits an advertised tile; the second duplicates its predecessor.
        for entries in [[firstEntry], [firstEntry, firstEntry]] {
            let index = MapTilePackFormat.index(entries)
            let header = try MapTilePackFormat.header(manifest: largerManifest, index: index,
                                                      count: entries.count, rawBytes: 0)
            #expect(throws: MapTilePack.PackError.corruptPack) {
                try MapTilePackFormat.decode(header: header, manifest: largerManifest, index: index)
            }
        }
    }

    @Test("Header and manifest integrity reject corruption, unsupported versions and huge URLs")
    func malformedMetadata() throws {
        let plan = try plan()
        let manifest = try MapTilePackFormat.manifest(plan: plan, metadata: metadata())
        let index = MapTilePackFormat.index([MapTilePackFormat.Entry(tile: plan.tiles[0], offset: 0, length: 0, checksum: 0)])
        let original = try MapTilePackFormat.header(manifest: manifest, index: index, count: 1, rawBytes: 0)
        var version = original
        version[8] = 2
        #expect(throws: MapTilePack.PackError.unsupportedFormat) { try MapTilePackFormat.decodeHeader(version) }
        var corrupt = manifest
        corrupt[0] ^= 1
        #expect(throws: MapTilePack.PackError.corruptPack) {
            try MapTilePackFormat.decode(header: original, manifest: corrupt, index: index)
        }
        let malformed = Data("{}".utf8)
        let checkedHeader = try MapTilePackFormat.header(manifest: malformed, index: index, count: 1, rawBytes: 0)
        #expect(throws: MapTilePack.PackError.corruptPack) {
            try MapTilePackFormat.decode(header: checkedHeader, manifest: malformed, index: index)
        }
        let hugeURL = try #require(URL(string: "https://example.test/" + String(repeating: "x", count: 20_000)))
        let hugeMetadata = try MapSourceMetadata(attribution: "Credit", license: "License", licenseURL: hugeURL,
                                                 sourceURL: hugeURL, sourceRevision: "revision")
        #expect(throws: MapTilePack.PackError.invalidConfiguration) {
            try MapTilePackFormat.manifest(plan: plan, metadata: hugeMetadata)
        }
    }

    private func plan() throws -> MapTilePackPlan {
        let bounds = try MapCoverage.Bounds(southwest: MapCoordinate(latitude: 1, longitude: 1),
                                           northeast: MapCoordinate(latitude: 2, longitude: 2))
        return try MapTilePackPlan(bounds: bounds, zoomRange: 2...2, maximumBytes: 10)
    }

    private func metadata() throws -> MapSourceMetadata {
        let url = try #require(URL(string: "https://example.test/source"))
        return try MapSourceMetadata(attribution: "Credit", license: "License", licenseURL: url,
                                     sourceURL: url, sourceRevision: "revision")
    }
}
