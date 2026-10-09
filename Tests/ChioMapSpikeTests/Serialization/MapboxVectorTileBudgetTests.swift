@testable import ChioMapSpike
import Foundation
import Testing

struct MapboxVectorTileBudgetTests {
    @Test("MVT accepts the exact layer allowance and rejects one more valid layer")
    func layerBoundary() throws {
        let count = MapboxVectorTileDecoder.maximumLayers
        let accepted = (0..<count).flatMap { layer(name: "layer-\($0)", features: [line]) }
        #expect(try decode(accepted).count == count)
        expectBudget(accepted + layer(name: "layer-\(count)", features: [line]))
    }

    @Test("MVT raw feature admission is independent of the smaller canonical feature allowance")
    func rawFeatureBoundary() throws {
        let count = MapboxVectorTileDecoder.maximumFeatures
        let accepted = layer(name: "t", features: Array(repeating: line, count: count))
        #expect(try decode(accepted)[0].features.count == count)
        expectBudget(layer(name: "t", features: Array(repeating: line, count: count + 1)))
    }

    @Test("MVT admits exact combined key/value table entries and rejects the next valid value")
    func tableBoundary() throws {
        let count = MapboxVectorTileDecoder.maximumTableEntries
        let entry = integer(5, 0)
        let values = Array(repeating: entry, count: count - 1)
        let item = feature(words: [9,0,0,10,2,2], tags: [0,0])
        let accepted = layer(name: "t", features: [item], keys: ["k"], values: values)
        #expect(try decode(accepted)[0].features[0].properties["k"] == .unsigned(0))
        expectBudget(layer(name: "t", features: [item], keys: ["k"], values: values + [entry]))
    }

    @Test("MVT geometry words share one admission budget across all raw features")
    func wordBoundary() throws {
        // A valid 24-vertex line has 50 words; 20,000 such records consume
        // exactly one million words while respecting every other wire allowance.
        let words: [UInt32] = [9,0,0,UInt32(23 << 3) | 2]
            + Array(repeating: [UInt32(2),UInt32(0)], count: 23).flatMap { $0 }
        let count = MapboxVectorTileDecoder.maximumWords / words.count
        #expect(words.count == 50 && count <= MapboxVectorTileDecoder.maximumFeatures)
        #expect(count * words.count == MapboxVectorTileDecoder.maximumWords)
        let item = feature(words: words)
        let accepted = layer(name: "t", features: Array(repeating: item, count: count))
        let decoded = try decode(accepted)
        #expect(decoded[0].features.reduce(0) { $0 + $1.words.count }
                == MapboxVectorTileDecoder.maximumWords)
        // Two extra parameter words preserve a valid LineTo rather than causing
        // an unrelated geometry/tag failure; the raw feature count is unchanged.
        let longerWords: [UInt32] = [9,0,0,UInt32(24 << 3) | 2]
            + Array(repeating: [UInt32(2),UInt32(0)], count: 24).flatMap { $0 }
        let over = Array(repeating: item, count: count - 1) + [feature(words: longerWords)]
        expectBudget(layer(name: "t", features: over))
    }

    @Test("MVT text admission counts all layer/key/value UTF-8 bytes")
    func textBoundary() throws {
        // Layer name and the single key consume two bytes. Every string value
        // stays within the separate 16-KiB string allowance.
        let remaining = MapboxVectorTileDecoder.maximumTextBytes - 2
        let full = remaining / 16_384
        let tail = remaining % 16_384
        let large = message(1, Array(repeating: UInt8(97), count: 16_384))
        let tailValue = message(1, Array(repeating: UInt8(97), count: tail))
        let values = Array(repeating: large, count: full) + [tailValue]
        let item = feature(words: [9,0,0,10,2,2], tags: [0,0])
        let accepted = layer(name: "t", features: [item], keys: ["k"], values: values)
        #expect(try decode(accepted)[0].features[0].properties["k"]?.string?.utf8.count == 16_384)
        #expect(tail + 1 <= 16_384)
        let overValues = Array(repeating: large, count: full)
            + [message(1, Array(repeating: UInt8(97), count: tail + 1))]
        expectBudget(layer(name: "t", features: [item], keys: ["k"], values: overValues))
    }

    @Test("MVT values preserve signed integers, ZigZag extrema and finite fixed-width numbers")
    func numericValues() throws {
        let keys = ["signed", "zigzag", "minimum", "float", "double", "false", "true"]
        let values = [integer(4, UInt64(bitPattern: -17)), integer(6, 33), integer(6, UInt64.max),
                      fixed(number: 2, bits: UInt64(Float(-3.25).bitPattern), count: 4),
                      fixed(number: 3, bits: Double(1.25).bitPattern, count: 8),
                      integer(7, 0), integer(7, 1)]
        let tags = (0..<keys.count).flatMap { [UInt32($0), UInt32($0)] }
        let item = feature(words: [9,0,0,10,2,2], tags: tags)
        let properties = try decode(layer(name: "t", features: [item], keys: keys, values: values))[0].features[0].properties
        #expect(properties["signed"] == .signed(-17))
        #expect(properties["zigzag"] == .signed(-17))
        #expect(properties["minimum"] == .signed(Int64.min))
        #expect(properties["float"] == .number(-3.25))
        #expect(properties["double"] == .number(1.25))
        #expect(properties["false"] == .boolean(false) && properties["true"] == .boolean(true))
        for invalid in [fixed(number: 2, bits: UInt64(Float.infinity.bitPattern), count: 4),
                        fixed(number: 2, bits: UInt64(Float.nan.bitPattern), count: 4),
                        fixed(number: 3, bits: Double(-Double.infinity).bitPattern, count: 8),
                        fixed(number: 3, bits: Double.nan.bitPattern, count: 8)] {
            #expect(throws: MapboxVectorTileDecoder.ValidationError.invalidValue) {
                try decode(layer(name: "t", features: [line], values: [invalid]))
            }
        }
    }

    private var line: [UInt8] { feature(words: [9,0,0,10,2,2]) }

    private func decode(_ bytes: [UInt8]) throws -> [MapboxVectorTileDecoder.Layer] {
        #expect(bytes.count <= MapboxVectorTileDecoder.maximumBytes)
        return try MapboxVectorTileDecoder.decode(Data(bytes))
    }

    private func expectBudget(_ bytes: [UInt8]) {
        #expect(bytes.count <= MapboxVectorTileDecoder.maximumBytes)
        #expect(throws: MapboxVectorTileDecoder.ValidationError.budgetExceeded) {
            try MapboxVectorTileDecoder.decode(Data(bytes))
        }
    }

    private func layer(name: String, features: [[UInt8]], keys: [String] = [], values: [[UInt8]] = []) -> [UInt8] {
        let header = integer(15, 2) + message(1, Array(name.utf8)) + integer(5, 4096)
        let tables = keys.flatMap { message(3, Array($0.utf8)) } + values.flatMap { message(4, $0) }
        return message(3, header + tables + features.flatMap { message(2, $0) })
    }

    private func feature(words: [UInt32], tags: [UInt32] = []) -> [UInt8] {
        integer(3, 2) + message(2, tags.flatMap { varint(UInt64($0)) })
            + message(4, words.flatMap { varint(UInt64($0)) })
    }
    private func fixed(number: UInt64, bits: UInt64, count: Int) -> [UInt8] {
        varint(number << 3 | (count == 4 ? 5 : 1))
            + (0..<count).map { UInt8(truncatingIfNeeded: bits >> ($0 * 8)) }
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
