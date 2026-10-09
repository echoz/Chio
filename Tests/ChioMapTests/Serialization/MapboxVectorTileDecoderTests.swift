@testable import ChioMaps
@testable import Chio
import Foundation
import Testing

struct MapboxVectorTileDecoderTests {
    @Test("Unchecked geometry extents reject before arithmetic")
    func invalidExtent() {
        let line = MapboxVectorTileDecoder.Feature(id: nil, type: 2, properties: [:], words: [9,0,0,10,2,2])
        for extent in [Int.min, -1, 0, 65_537, Int.max] {
            #expect(throws: MapboxVectorTileDecoder.ValidationError.invalidLayer) {
                try MapboxVectorTileDecoder.geometry(line, extent: extent)
            }
        }
    }

    @Test("MVT layer decoding handles reordered fields, typed values and packed/unpacked words")
    func wireSemantics() throws {
        let input = tile(layer(name: "transportation", features: [
            feature(type: 2, words: [9, 0, 0, 10, 20, 0], tags: [0, 0], id: UInt64.max),
        ], keys: ["class"], values: [message(1, Array("primary".utf8))]))
        let layers = try MapboxVectorTileDecoder.decode(Data(input))
        #expect(layers.count == 1 && layers[0].extent == 4096)
        #expect(layers[0].features[0].id == UInt64.max)
        #expect(layers[0].features[0].properties["class"] == .string("primary"))
        var unpacked = integer(3, 2)
        for word in [UInt32(9), 0, 0, 10, 20, 0] { unpacked += integer(4, UInt64(word)) }
        let replacement = try MapboxVectorTileDecoder.decode(Data(tile(layer(name: "road", features: [unpacked]))))
        #expect(replacement[0].features[0].words == layers[0].features[0].words)
    }

    @Test("Multipart cursors survive ClosePath and polygon holes stay attached to their exterior")
    func geometrySemantics() throws {
        // Two exteriors and a hole, from the MVT 2.1 specification's example.
        let words: [UInt32] = [9,0,0,26,20,0,0,20,19,0,15,
                               9,22,2,26,18,0,0,18,17,0,15,
                               9,4,13,26,0,8,8,0,0,7,15]
        let source = MapboxVectorTileDecoder.Feature(id: nil, type: 3, properties: [:], words: words)
        guard case .polygons(let polygons) = try MapboxVectorTileDecoder.geometry(source, extent: 4096)
        else { Issue.record("Expected polygons"); return }
        #expect(polygons.count == 2 && polygons[0].count == 1 && polygons[1].count == 2)
        #expect(polygons[1][0][0] == .init(x: 11, y: 11))
        #expect(polygons[1][1][0] == .init(x: 13, y: 13))
        #expect(polygons[1][1].first == polygons[1][1].last)
        let lines = MapboxVectorTileDecoder.Feature(id: nil, type: 2, properties: [:],
            words: [9,4,4,18,0,16,16,0,9,17,17,10,4,8])
        guard case .lines(let paths) = try MapboxVectorTileDecoder.geometry(lines, extent: 4096)
        else { Issue.record("Expected lines"); return }
        #expect(paths.count == 2 && paths[1][0] == .init(x: 1, y: 1))
    }

    @Test("MVT wire truncation, overflow, tags, required fields and unsupported versions reject")
    func invalidWire() throws {
        let validFeature = feature(type: 2, words: [9,0,0,10,2,2])
        let valid = tile(layer(name: "road", features: [validFeature]))
        for malformed in [
            [UInt8(0)], [UInt8(26), 127], [UInt8(24)] + Array(repeating: 255, count: 10),
            tile(layer(name: "road", features: [validFeature], version: 1)),
            tile(layer(name: "road", features: [validFeature], extent: 0)),
            tile(layer(name: "road", features: [validFeature], extent: 65_537)),
            tile(layer(name: "road", features: [feature(type: 2, words: [9,0,0,10,2,2], tags: [0])])),
            tile(layer(name: "road", features: [feature(type: 2, words: [9,0,0,10,2,2], tags: [0,0])])),
            tile(layer(name: "road", features: [validFeature], keys: ["k"], values: [integer(7, 2)])),
            tile(layer(name: "road", features: [validFeature], keys: ["k"],
                       values: [integer(5, 1) + integer(7, 1)])),
            valid + valid,
            tile(message(1, Array("road".utf8)) + message(2, validFeature)),
        ] {
            #expect(throws: (any Error).self) { try MapboxVectorTileDecoder.decode(Data(malformed)) }
        }
        for length in 1..<valid.count {
            #expect(throws: (any Error).self) { try MapboxVectorTileDecoder.decode(Data(valid.prefix(length))) }
        }
        #expect(throws: MapboxVectorTileDecoder.ValidationError.budgetExceeded) {
            try MapboxVectorTileDecoder.decode(Data(repeating: 0, count: MapboxVectorTileDecoder.maximumBytes + 1))
        }
    }

    @Test("Geometry command state, zero segments, range, ring orientation and budgets reject")
    func invalidGeometry() throws {
        let invalidLines: [[UInt32]] = [
            [], [9,0], [0], [10,0,0], [9,0,0], [9,0,0,10,0,0],
            [9,0,0,11,2,2], [9,0,0,10,UInt32.max,0], [17,0,0,2,2,10,2,2],
        ]
        for words in invalidLines {
            let source = MapboxVectorTileDecoder.Feature(id: nil, type: 2, properties: [:], words: words)
            #expect(throws: (any Error).self) { try MapboxVectorTileDecoder.geometry(source, extent: 4096) }
        }
        let invalidPolygons: [[UInt32]] = [
            [9,0,0,18,2,0,0,2], // Missing ClosePath.
            [9,0,0,18,0,2,2,0,15], // Hole before an exterior.
            [9,0,0,18,2,0,2,0,15], // Collinear ring.
            [9,0,0,18,2,0,0,2,23], // ClosePath count 2.
            [9,0,0,26,2,0,0,2,1,1,15], // Explicit zero-length close.
        ]
        for words in invalidPolygons {
            let source = MapboxVectorTileDecoder.Feature(id: nil, type: 3, properties: [:], words: words)
            #expect(throws: (any Error).self) { try MapboxVectorTileDecoder.geometry(source, extent: 4096) }
        }
        let excessive: [UInt32] = [9,0,0, UInt32(MapLimits.pathVertices << 3) | 2]
            + Array(repeating: [UInt32(2),UInt32(0)], count: MapLimits.pathVertices).flatMap { $0 }
        let source = MapboxVectorTileDecoder.Feature(id: nil, type: 2, properties: [:], words: excessive)
        #expect(throws: (any Error).self) { try MapboxVectorTileDecoder.geometry(source, extent: 4096) }
    }

    private func tile(_ layer: [UInt8]) -> [UInt8] { message(3, layer) }

    private func layer(name: String, features: [[UInt8]], keys: [String] = [], values: [[UInt8]] = [],
                       version: UInt64 = 2, extent: UInt64 = 4096) -> [UInt8] {
        message(1, Array(name.utf8)) + features.flatMap { message(2, $0) }
            + keys.flatMap { message(3, Array($0.utf8)) } + values.flatMap { message(4, $0) }
            + integer(5, extent) + integer(15, version)
    }

    private func feature(type: UInt64, words: [UInt32], tags: [UInt32] = [], id: UInt64? = nil) -> [UInt8] {
        (id.map { integer(1, $0) } ?? []) + message(2, tags.flatMap { varint(UInt64($0)) })
            + integer(3, type) + message(4, words.flatMap { varint(UInt64($0)) })
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
