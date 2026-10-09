@testable import ChioMapSpike
import Foundation
import Testing

struct OpenMapTilesAdapterTests {
    @Test("The OpenMapTiles subset preserves multipart geometry, holes, context and snapshot identities")
    func sourceContract() throws {
        let tile = try MapTileCoordinate(zoom: 14, x: 12918, y: 8133)
        let metadata = try credit()
        let adapter = OpenMapTilesAdapter(tile: tile, metadata: metadata)
        let polygons: [UInt32] = [9,0,0,26,20,0,0,20,19,0,15,
                                  9,22,2,26,18,0,0,18,17,0,15,
                                  9,4,13,26,0,8,8,0,0,7,15]
        let lines: [UInt32] = [9,4,4,18,0,16,16,0,9,17,17,10,4,8]
        let bytes = layer("water", type: 3, words: polygons)
            + layer("transportation", type: 2, words: lines, sourceClass: "primary", name: "Test Road")
        let input = Data(bytes)
        let source = try adapter.adapt(input)
        #expect(try source.metadata == metadata && source.coverage == tile.coverage)
        #expect(source.dataset.features.count == 4)
        #expect(Set(source.dataset.features.map(\.id)).count == 4)
        #expect(source.dataset.features.filter { $0.kind == .primaryRoad }.allSatisfy { $0.name == "Test Road" })
        let water = source.dataset.features.filter { $0.kind == .water }
        guard case .polygon(let second) = water[1].geometry else { Issue.record("Expected water polygon"); return }
        #expect(second.rings.count == 2)
        #expect(source == (try adapter.adapt(input)))
        #expect(input == Data(bytes))
    }

    @Test("Unsupported layers and road classes skip deliberately while supported malformed geometry rejects")
    func subsetPolicy() throws {
        let adapter = OpenMapTilesAdapter(tile: try .init(zoom: 14, x: 12918, y: 8133), metadata: try credit())
        let validLine: [UInt32] = [9,0,0,10,2,2]
        let ignored = layer("waterway", type: 2, words: validLine)
            + layer("transportation_name", type: 2, words: validLine, sourceClass: "primary", name: "Label")
            + layer("transportation", type: 2, words: validLine, sourceClass: "service")
            + layer("landcover", type: 3, words: [9,0,0,18,2,0,0,2,15], sourceClass: "grass")
        #expect(try adapter.adapt(Data(ignored)).dataset.features.isEmpty)
        for data in [layer("water", type: 2, words: validLine),
                     layer("transportation", type: 2, words: [9,0,0], sourceClass: "primary"),
                     layer("building", type: 3, words: [9,0,0,18,2,0,0,2])] {
            #expect(throws: (any Error).self) { try adapter.adapt(Data(data)) }
        }
    }

    @Test("Real bundled OpenFreeMap bytes adapt without a GeoJSON intermediate")
    func realFixture() throws {
        let url = try #require(Bundle.module.url(forResource: "openfreemap-singapore", withExtension: "pbf",
                                                 subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        let layers = try MapboxVectorTileDecoder.decode(data)
        #expect(data.count == 104_054)
        #expect(layers.contains { $0.name == "transportation" && $0.features.count == 377 })
        let source = try OpenMapTilesAdapter(tile: .init(zoom: 14, x: 12919, y: 8133), metadata: credit()).adapt(data)
        // Independently counted from the pinned raw tile's integer commands,
        // including multipart expansion and explicit ring closure vertices.
        #expect(source.dataset.features.count == 384)
        #expect(source.dataset.vertexCount == 3_365)
        let kinds = Dictionary(grouping: source.dataset.features, by: \.kind).mapValues { $0.count }
        #expect(kinds == [.building: 136, .primaryRoad: 138, .road: 76, .water: 34])
        let holes = source.dataset.features.reduce(0) { count, feature in
            if case .polygon(let polygon) = feature.geometry { count + polygon.rings.count - 1 }
            else { count }
        }
        #expect(holes == 2)
        let anchor = try #require(source.dataset.features.first { $0.id == "mvt/14/12919/8133/water/0/10970/0" })
        guard case .polygon(let polygon) = anchor.geometry else { Issue.record("Expected water polygon"); return }
        let first = try #require(polygon.rings.first?.coordinates.first)
        // Original tile point (563,4160), extent 4096; retained outside coverage.
        #expect(abs(first.longitude - 103.86776626110077) < 0.000_000_000_001)
        #expect(abs(first.latitude - 1.273965753978455) < 0.000_000_000_001)
        #expect(!source.coverage.contains(first))
        for identity in ["mvt/14/12919/8133/water/2/120087393/0", "mvt/14/12919/8133/water/3/128407283/0"] {
            let feature = try #require(source.dataset.features.first { $0.id == identity })
            guard case .polygon(let water) = feature.geometry else { Issue.record("Expected water polygon"); return }
            #expect(water.rings.count == 2)
        }
    }

    @Test("Canonical admission accepts exactly 4000 supported parts and rejects the next whole feature")
    func canonicalFeatureBoundary() throws {
        let adapter = OpenMapTilesAdapter(tile: try .init(zoom: 14, x: 12919, y: 8133), metadata: try credit())
        // Every raw record is one complete two-vertex road. Repeated source IDs
        // remain distinct through tile/layer/ordinal/part identities. Both inputs
        // are below decoder byte, raw-feature, word and canonical vertex limits.
        let exact = Data(layer("transportation", type: 2, words: [9,0,0,10,2,2], sourceClass: "primary", featureCopies: 4_000))
        let source = try adapter.adapt(exact)
        #expect(source.dataset.features.count == 4_000)
        #expect(source.dataset.vertexCount == 8_000)
        #expect(Set(source.dataset.features.map(\.id)).count == 4_000)
        let over = Data(layer("transportation", type: 2, words: [9,0,0,10,2,2], sourceClass: "primary", featureCopies: 4_001))
        #expect(try MapboxVectorTileDecoder.decode(over)[0].features.count == 4_001)
        #expect(throws: MapValidationError.budgetExceeded) { try adapter.adapt(over) }
    }

    @Test("Tile segments outside the shortest-edge geographic subset reject instead of collapsing")
    func wideEdges() throws {
        let adapter = OpenMapTilesAdapter(tile: try .init(zoom: 0, x: 0, y: 0), metadata: try credit())
        // (0,2048) -> (4096,2048) is a full-world segment, not a zero-length seam.
        for endX in [UInt32(2048), 4096] {
            let data = Data(layer("transportation", type: 2, words: [9,0,4096,10,endX * 2,0], sourceClass: "primary"))
            #expect(throws: MapboxVectorTileDecoder.ValidationError.invalidGeometry) { try adapter.adapt(data) }
        }
        let local = Data(layer("transportation", type: 2, words: [9,0,4096,10,2048,0], sourceClass: "primary"))
        #expect(try adapter.adapt(local).dataset.features.count == 1)
    }

    private func credit() throws -> MapSourceMetadata {
        let url = try #require(URL(string: "https://example.test/source"))
        return try MapSourceMetadata(attribution: "Test provider", license: "Test license", licenseURL: url,
                                     sourceURL: url, sourceRevision: "snapshot")
    }

    private func layer(_ name: String, type: UInt64, words: [UInt32], sourceClass: String = "", name label: String = "", featureCopies: Int = 1) -> [UInt8] {
        var feature = integer(1, 1) + integer(3, type) + message(4, words.flatMap { varint(UInt64($0)) })
        var tables: [UInt8] = []
        var tags: [UInt8] = []
        for (index, pair) in [("class", sourceClass), ("name", label)].enumerated() {
            tables += message(3, Array(pair.0.utf8)) + message(4, message(1, Array(pair.1.utf8)))
            tags += varint(UInt64(index)) + varint(UInt64(index))
        }
        feature += message(2, tags)
        return message(3, integer(15, 2) + message(1, Array(name.utf8)) + integer(5, 4096)
                       + tables + Array(repeating: message(2, feature), count: featureCopies).flatMap { $0 })
    }
    private func integer(_ number: UInt64, _ value: UInt64) -> [UInt8] { varint(number << 3) + varint(value) }
    private func message(_ number: UInt64, _ bytes: [UInt8]) -> [UInt8] {
        varint(number << 3 | 2) + varint(UInt64(bytes.count)) + bytes
    }
    private func varint(_ input: UInt64) -> [UInt8] {
        var value = input
        var bytes: [UInt8] = []
        while value >= 128 { bytes.append(UInt8(value & 127) | 128); value >>= 7 }
        bytes.append(UInt8(value))
        return bytes
    }
}
