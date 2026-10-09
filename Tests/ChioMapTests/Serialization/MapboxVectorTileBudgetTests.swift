@testable import ChioMaps
@testable import Chio
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

    @Test("MVT admits 4,000 independent line paths and rejects the next complete path")
    func linePathBoundary() throws {
        let paths = (0..<4_000).map { [(0, $0), (1, $0)] }
        let accepted = geometryWords(paths: paths, closed: false)
        // Each two-vertex path contributes six words, far below the wire budget.
        #expect(accepted.count == 24_000)
        guard case .lines(let decoded) = try geometry(accepted, type: 2) else {
            Issue.record("Expected independent line paths")
            return
        }
        #expect(decoded.count == 4_000 && decoded.allSatisfy { $0.count == 2 })
        let over = geometryWords(paths: paths + [[(0, 4_000), (1, 4_000)]], closed: false)
        #expect(over.count == 24_006)
        expectGeometryBudget(over, type: 2)
    }

    @Test("MVT independent polygon exteriors do not consume one polygon's ring allowance")
    func polygonPathBoundary() throws {
        let paths = exteriorTriangles(count: 4_000)
        let accepted = geometryWords(paths: paths, closed: true)
        // Three explicit vertices plus closure: 16,000 vertices and 36,000 words.
        #expect(accepted.count == 36_000)
        guard case .polygons(let decoded) = try geometry(accepted, type: 3) else {
            Issue.record("Expected independent polygon exteriors")
            return
        }
        #expect(decoded.count == 4_000)
        #expect(decoded.allSatisfy { $0.count == 1 && $0[0].count == 4 })
        let over = geometryWords(paths: exteriorTriangles(count: 4_001), closed: true)
        #expect(over.count == 36_009)
        expectGeometryBudget(over, type: 3)
    }

    @Test("MVT preserves all 257 disjoint exterior parts in a single building record")
    func separateExteriorsBeyondRingAllowance() throws {
        let words = geometryWords(paths: exteriorTriangles(count: 257), closed: true)
        guard case .polygons(let polygons) = try geometry(words, type: 3) else {
            Issue.record("Expected separate building parts")
            return
        }
        #expect(polygons.count == 257)
        #expect(polygons.allSatisfy { $0.count == 1 })
        #expect(polygons.reduce(0) { $0 + $1[0].count } == 1_028)
    }

    @Test("MVT bounds the rings of each actual polygon at 256 including its exterior")
    func polygonRingBoundary() throws {
        let exterior = [(0, 0), (4_096, 0), (4_096, 4_096), (0, 4_096)]
        // Counterclockwise, mutually disjoint two-unit squares lie inside the exterior.
        let holes = (0..<256).map { index in
            let x = 10 + (index % 16) * 5, y = 10 + (index / 16) * 5
            return [(x, y), (x, y + 2), (x + 2, y + 2), (x + 2, y)]
        }
        let accepted = geometryWords(paths: [exterior] + Array(holes.prefix(255)), closed: true)
        guard case .polygons(let polygons) = try geometry(accepted, type: 3) else {
            Issue.record("Expected an exterior with its holes")
            return
        }
        #expect(polygons.count == 1 && polygons[0].count == 256)
        #expect(polygons[0].reduce(0) { $0 + $1.count } == 1_280)
        expectGeometryBudget(geometryWords(paths: [exterior] + holes, closed: true), type: 3)
    }

    @Test("MVT admits 200,000 raw record vertices and rejects exactly one extra vertex")
    func recordVertexBoundary() throws {
        // Alternating x coordinates keep 20,000 distinct consecutive vertices in
        // each path inside the tile's integer coordinate allowance.
        func paths(counts: [Int]) -> [[(Int, Int)]] {
            counts.enumerated().map { row, count in (0..<count).map { ($0 % 2, row) } }
        }
        let accepted = geometryWords(paths: paths(counts: Array(repeating: 20_000, count: 10)), closed: false)
        #expect(accepted.count == 400_020 && accepted.count < 1_000_000)
        guard case .lines(let lines) = try geometry(accepted, type: 2) else {
            Issue.record("Expected vertex-bounded lines")
            return
        }
        #expect(lines.count == 10 && lines.allSatisfy { $0.count == 20_000 })
        #expect(lines.reduce(0) { $0 + $1.count } == 200_000)
        // Shortening one full path by one and adding a valid two-vertex path
        // exceeds only the record total, preserving every individual path bound.
        let counts = Array(repeating: 20_000, count: 9) + [19_999, 2]
        #expect(counts.reduce(0, +) == 200_001)
        let over = geometryWords(paths: paths(counts: counts), closed: false)
        #expect(over.count == 400_024 && over.count < 1_000_000)
        expectGeometryBudget(over, type: 2)
    }

    @Test("MVT classifies one extra line vertex or polygon closure vertex as a path budget failure")
    func individualPathBoundary() throws {
        let line = (0..<MapLimits.pathVertices).map { ($0 % 2, 0) }
        guard case .lines(let accepted) = try geometry(geometryWords(paths: [line], closed: false), type: 2) else {
            Issue.record("Expected an exact-limit line"); return
        }
        #expect(accepted.count == 1 && accepted[0].count == MapLimits.pathVertices)
        expectGeometryBudget(geometryWords(paths: [line + [(0, 0)]], closed: false), type: 2)

        // Collinear boundary samples preserve a nonzero clockwise rectangle.
        // ClosePath contributes the final vertex to the same path allowance.
        func rectangle(vertices: Int) -> [(Int, Int)] {
            (0..<(vertices - 2)).map { ($0, 0) } + [(vertices - 3, 1), (0, 1)]
        }
        let exact = geometryWords(paths: [rectangle(vertices: MapLimits.pathVertices - 1)], closed: true)
        guard case .polygons(let polygons) = try geometry(exact, type: 3) else {
            Issue.record("Expected an exact-limit polygon"); return
        }
        #expect(polygons.count == 1 && polygons[0][0].count == MapLimits.pathVertices)
        expectGeometryBudget(geometryWords(paths: [rectangle(vertices: MapLimits.pathVertices)], closed: true), type: 3)
    }

    @Test("Malformed oversized paths remain geometry failures before budget-only fallback")
    func malformedOversizedPaths() throws {
        let path = (0...MapLimits.pathVertices).map { ($0 % 2, 0) }
        let over = geometryWords(paths: [path], closed: false)
        var repeated = over
        repeated[repeated.count - 2] = 0 // Zero-length final LineTo.
        var invalidCoordinate = over
        invalidCoordinate[invalidCoordinate.count - 2] = 65_538 // Beyond extent * 8.
        // A malformed later path must still reject after a complete over-budget one.
        let malformed = [Array(over.dropLast()), repeated, invalidCoordinate, over + [9, 0, 0]]
        for words in malformed {
            #expect(throws: MapboxVectorTileDecoder.ValidationError.invalidGeometry) {
                try geometry(words, type: 2)
            }
        }
        // An oversized polygon must still supply a valid closure and nonzero area.
        let collinear = geometryWords(paths: [Array(0..<MapLimits.pathVertices).map { ($0, 0) }], closed: true)
        for words in [Array(collinear.dropLast()), collinear] {
            #expect(throws: MapboxVectorTileDecoder.ValidationError.invalidGeometry) {
                try geometry(words, type: 3)
            }
        }
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

    private func feature(words: [UInt32], tags: [UInt32] = [], type: UInt32 = 2) -> [UInt8] {
        integer(3, UInt64(type)) + message(2, tags.flatMap { varint(UInt64($0)) })
            + message(4, words.flatMap { varint(UInt64($0)) })
    }

    private func geometry(_ words: [UInt32], type: UInt32) throws -> MapboxVectorTileDecoder.Geometry {
        let record = try decode(layer(name: "geometry", features: [feature(words: words, type: type)]))[0].features[0]
        #expect(record.words.count == words.count)
        return try MapboxVectorTileDecoder.geometry(record, extent: 4_096)
    }

    private func expectGeometryBudget(_ words: [UInt32], type: UInt32) {
        // Wire decoding must succeed so a geometry admission failure cannot be
        // accidentally satisfied by a separate tile-wide word or byte limit.
        do {
            let record = try decode(layer(name: "geometry", features: [feature(words: words, type: type)]))[0].features[0]
            #expect(record.words.count == words.count)
            #expect(throws: MapboxVectorTileDecoder.ValidationError.budgetExceeded) {
                try MapboxVectorTileDecoder.geometry(record, extent: 4_096)
            }
        } catch {
            Issue.record("Wire decoding unexpectedly failed: \(error)")
        }
    }

    private func exteriorTriangles(count: Int) -> [[(Int, Int)]] {
        (0..<count).map { index in
            let x = (index % 64) * 4, y = (index / 64) * 4
            return [(x, y), (x + 2, y), (x, y + 2)]
        }
    }

    private func geometryWords(paths: [[(Int, Int)]], closed: Bool) -> [UInt32] {
        var words: [UInt32] = []
        var cursor = (0, 0)
        func parameter(_ delta: Int) -> UInt32 {
            UInt32(truncatingIfNeeded: (delta << 1) ^ (delta >> (Int.bitWidth - 1)))
        }
        for path in paths {
            precondition(path.count >= (closed ? 3 : 2))
            words.append(9) // MoveTo(1).
            for (index, point) in path.enumerated() {
                if index == 1 { words.append(UInt32((path.count - 1) << 3) | 2) }
                words.append(parameter(point.0 - cursor.0))
                words.append(parameter(point.1 - cursor.1))
                cursor = point
            }
            if closed { words.append(15) } // ClosePath(1) does not move the cursor.
        }
        return words
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
