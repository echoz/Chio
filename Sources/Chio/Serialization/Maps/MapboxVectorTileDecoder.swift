import Foundation

/// A bounded MVT v2 reader for the supported OpenMapTiles subset.
/// Unknown ordinary protobuf fields are skipped; groups and other MVT versions
/// are rejected. Feature geometry remains in integer tile units until adaptation.
enum MapboxVectorTileDecoder {
    static let maximumBytes = 16 * 1_024 * 1_024
    static let maximumLayers = 64
    static let maximumFeatures = 20_000
    static let maximumTableEntries = 65_536
    static let maximumWords = 1_000_000
    static let maximumTextBytes = 2 * 1_024 * 1_024

    struct Layer {
        let name: String
        let extent: Int
        let features: [Feature]
    }

    struct Feature {
        let id: UInt64?
        let type: UInt32
        let properties: [String: Value]
        let words: [UInt32]
    }

    enum Value {
        case string(String), signed(Int64), unsigned(UInt64), number(Double), boolean(Bool)

        var string: String? {
            if case .string(let text) = self { text } else { nil }
        }
    }

    struct Point {
        let x: Int64
        let y: Int64
    }

    enum Geometry {
        case lines([[Point]])
        /// Each part starts with its exterior and retains its following holes.
        case polygons([[[Point]]])
    }

    typealias ValidationError = OpenMapTilesAdapter.ValidationError

    static func decode(_ data: Data) throws -> [Layer] {
        guard data.count <= maximumBytes else { throw ValidationError.budgetExceeded }
        var reader = Reader(bytes: Array(data))
        var budget = Budget()
        var layers: [Layer] = []
        var names: Set<String> = []
        while let field = try reader.field() {
            if field.number == 3 {
                let layer = try decodeLayer(reader.message(field), budget: &budget)
                guard layers.count < maximumLayers else { throw ValidationError.budgetExceeded }
                guard names.insert(layer.name).inserted else { throw ValidationError.invalidLayer }
                layers.append(layer)
            } else { try reader.skip(field) }
        }
        return layers
    }

    static func geometry(_ feature: Feature, extent: Int) throws -> Geometry {
        guard (1...65_536).contains(extent) else { throw ValidationError.invalidLayer }
        guard feature.type == 2 || feature.type == 3 else { throw ValidationError.invalidGeometry }
        var offset = 0
        var cursor = Point(x: 0, y: 0)
        var paths: [[Point]] = []
        let bound = Int64(extent) * 8
        func command() throws -> (UInt32, Int) {
            guard offset < feature.words.count else { throw ValidationError.invalidGeometry }
            let word = feature.words[offset]
            offset += 1
            let count = Int(word >> 3)
            guard count > 0 else { throw ValidationError.invalidGeometry }
            return (word & 7, count)
        }
        func points(_ count: Int, into path: inout [Point]) throws {
            guard count <= MapLimits.pathVertices - path.count,
                  count <= (feature.words.count - offset) / 2
            else { throw ValidationError.invalidGeometry }
            for _ in 0..<count {
                let dx = zigzag(feature.words[offset])
                let dy = zigzag(feature.words[offset + 1])
                offset += 2
                let (x, xOverflow) = cursor.x.addingReportingOverflow(dx)
                let (y, yOverflow) = cursor.y.addingReportingOverflow(dy)
                guard !xOverflow, !yOverflow, (-bound...bound).contains(x), (-bound...bound).contains(y)
                else { throw ValidationError.invalidGeometry }
                cursor = Point(x: x, y: y)
                path.append(cursor)
            }
        }
        while offset < feature.words.count {
            let move = try command()
            guard move.0 == 1, move.1 == 1 else { throw ValidationError.invalidGeometry }
            var path: [Point] = []
            try points(1, into: &path)
            let line = try command()
            guard line.0 == 2, line.1 >= (feature.type == 3 ? 2 : 1)
            else { throw ValidationError.invalidGeometry }
            try points(line.1, into: &path)
            guard zip(path, path.dropFirst()).allSatisfy({ $0.0 != $0.1 })
            else { throw ValidationError.invalidGeometry }
            if feature.type == 3 {
                let close = try command()
                guard close.0 == 7, close.1 == 1, path.first != path.last,
                      path.count < MapLimits.pathVertices
                else { throw ValidationError.invalidGeometry }
                path.append(path[0])
                // ClosePath leaves cursor at the last LineTo, not at the first vertex.
            }
            guard paths.count < MapLimits.polygonRings,
                  paths.reduce(0, { $0 + $1.count }) + path.count <= MapLimits.sourceVertices
            else { throw ValidationError.budgetExceeded }
            paths.append(path)
        }
        guard !paths.isEmpty else { throw ValidationError.invalidGeometry }
        if feature.type == 2 { return .lines(paths) }
        var polygons: [[[Point]]] = []
        for ring in paths {
            // Coordinates are bounded to 8*65536 and paths to 20,000 points,
            // keeping every shoelace product and sum within Int64.
            let area = zip(ring, ring.dropFirst()).reduce(Int64(0)) {
                $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y
            }
            guard area != 0 else { throw ValidationError.invalidGeometry }
            if area > 0 {
                polygons.append([ring])
            } else {
                guard !polygons.isEmpty else { throw ValidationError.invalidGeometry }
                polygons[polygons.count - 1].append(ring)
            }
        }
        return .polygons(polygons)
    }

    private static func zigzag(_ word: UInt32) -> Int64 {
        Int64(word >> 1) ^ -Int64(word & 1)
    }

    private static func decodeLayer(_ input: Reader, budget: inout Budget) throws -> Layer {
        var reader = input
        var name: String?
        var version: UInt64?
        var extent: UInt64?
        var keys: [String] = []
        var values: [Value] = []
        var featureInputs: [Reader] = []
        while let field = try reader.field() {
            switch field.number {
            case 1:
                guard name == nil else { throw ValidationError.invalidLayer }
                name = try text(reader.message(field), budget: &budget)
            case 15:
                guard version == nil else { throw ValidationError.invalidLayer }
                version = try reader.integer(field)
            case 5:
                guard extent == nil else { throw ValidationError.invalidLayer }
                extent = try reader.integer(field)
            case 2:
                try budget.admitFeature()
                featureInputs.append(try reader.message(field))
            case 3:
                try budget.admitTableEntry()
                keys.append(try text(reader.message(field), budget: &budget))
            case 4:
                try budget.admitTableEntry()
                values.append(try value(reader.message(field), budget: &budget))
            default: try reader.skip(field)
            }
        }
        guard version == 2 else { throw ValidationError.unsupportedVersion }
        guard let name, !name.isEmpty, name.utf8.count <= 128,
              let extent, (1...65_536).contains(extent), Set(keys).count == keys.count
        else { throw ValidationError.invalidLayer }
        let features = try featureInputs.map { try feature($0, keys: keys, values: values, budget: &budget) }
        return Layer(name: name, extent: Int(extent), features: features)
    }

    private static func feature(_ input: Reader, keys: [String], values: [Value],
                                budget: inout Budget) throws -> Feature {
        var reader = input
        var id: UInt64?
        var type: UInt64?
        var tags: [UInt32] = []
        var words: [UInt32] = []
        while let field = try reader.field() {
            switch field.number {
            case 1:
                guard id == nil else { throw ValidationError.malformedWire }
                id = try reader.integer(field)
            case 2: try repeated(reader: &reader, field: field, output: &tags, budget: &budget)
            case 3:
                guard type == nil else { throw ValidationError.malformedWire }
                type = try reader.integer(field)
            case 4: try repeated(reader: &reader, field: field, output: &words, budget: &budget)
            default: try reader.skip(field)
            }
        }
        guard tags.count.isMultiple(of: 2) else { throw ValidationError.invalidTags }
        var properties: [String: Value] = [:]
        for index in stride(from: 0, to: tags.count, by: 2) {
            let key = Int(tags[index]), value = Int(tags[index + 1])
            guard key < keys.count, value < values.count, properties[keys[key]] == nil
            else { throw ValidationError.invalidTags }
            properties[keys[key]] = values[value]
        }
        guard let type, type <= 3, !words.isEmpty else { throw ValidationError.invalidGeometry }
        return Feature(id: id, type: UInt32(type), properties: properties, words: words)
    }

    private static func repeated(reader: inout Reader, field: Reader.Field, output: inout [UInt32],
                                 budget: inout Budget) throws {
        func append(_ value: UInt64) throws {
            guard let word = UInt32(exactly: value) else { throw ValidationError.malformedWire }
            try budget.admitWord()
            output.append(word)
        }
        if field.wire == 0 { try append(reader.integer(field)) }
        else {
            var packed = try reader.message(field)
            while !packed.atEnd { try append(packed.varint()) }
        }
    }

    private static func value(_ input: Reader, budget: inout Budget) throws -> Value {
        var reader = input
        var result: Value?
        while let field = try reader.field() {
            let candidate: Value
            switch field.number {
            case 1: candidate = .string(try text(reader.message(field), budget: &budget))
            case 2:
                guard field.wire == 5 else { throw ValidationError.malformedWire }
                candidate = .number(Double(Float(bitPattern: UInt32(try reader.fixed(count: 4)))))
            case 3:
                guard field.wire == 1 else { throw ValidationError.malformedWire }
                candidate = .number(Double(bitPattern: try reader.fixed(count: 8)))
            case 4: candidate = .signed(Int64(bitPattern: try reader.integer(field)))
            case 5: candidate = .unsigned(try reader.integer(field))
            case 6:
                let encoded = try reader.integer(field)
                candidate = .signed(Int64(bitPattern: encoded >> 1) ^ -Int64(encoded & 1))
            case 7:
                let encoded = try reader.integer(field)
                guard encoded <= 1 else { throw ValidationError.invalidValue }
                candidate = .boolean(encoded == 1)
            default:
                try reader.skip(field)
                continue
            }
            guard result == nil else { throw ValidationError.invalidValue }
            if case .number(let number) = candidate, !number.isFinite { throw ValidationError.invalidValue }
            result = candidate
        }
        guard let result else { throw ValidationError.invalidValue }
        return result
    }

    private static func text(_ reader: Reader, budget: inout Budget) throws -> String {
        let count = reader.end - reader.offset
        guard count <= 16_384 else { throw ValidationError.budgetExceeded }
        budget.textBytes += count
        guard budget.textBytes <= maximumTextBytes else { throw ValidationError.budgetExceeded }
        guard let text = String(bytes: reader.bytes[reader.offset..<reader.end], encoding: .utf8)
        else { throw ValidationError.malformedWire }
        return text
    }

    private struct Budget {
        var features = 0
        var tableEntries = 0
        var words = 0
        var textBytes = 0

        mutating func admitFeature() throws {
            features += 1
            guard features <= maximumFeatures else { throw ValidationError.budgetExceeded }
        }
        mutating func admitTableEntry() throws {
            tableEntries += 1
            guard tableEntries <= maximumTableEntries else { throw ValidationError.budgetExceeded }
        }
        mutating func admitWord() throws {
            words += 1
            guard words <= maximumWords else { throw ValidationError.budgetExceeded }
        }
    }

    /// Slices share immutable bytes; message nesting is fixed by the MVT schema.
    private struct Reader {
        let bytes: [UInt8]
        var offset: Int
        let end: Int

        init(bytes: [UInt8]) { self.bytes = bytes; offset = 0; end = bytes.count }
        init(bytes: [UInt8], offset: Int, end: Int) { self.bytes = bytes; self.offset = offset; self.end = end }
        var atEnd: Bool { offset == end }

        struct Field { let number: UInt64; let wire: UInt64 }

        mutating func field() throws -> Field? {
            if atEnd { return nil }
            let key = try varint()
            guard key >> 3 > 0, key >> 3 <= 536_870_911 else { throw ValidationError.malformedWire }
            return Field(number: key >> 3, wire: key & 7)
        }

        mutating func varint() throws -> UInt64 {
            var value: UInt64 = 0
            for index in 0..<10 {
                guard offset < end else { throw ValidationError.malformedWire }
                let byte = bytes[offset]
                offset += 1
                guard index != 9 || byte <= 1 else { throw ValidationError.malformedWire }
                value |= UInt64(byte & 127) << (index * 7)
                if byte & 128 == 0 { return value }
            }
            throw ValidationError.malformedWire
        }

        mutating func integer(_ field: Field) throws -> UInt64 {
            guard field.wire == 0 else { throw ValidationError.malformedWire }
            return try varint()
        }

        mutating func message(_ field: Field) throws -> Reader {
            guard field.wire == 2 else { throw ValidationError.malformedWire }
            let length = try varint()
            guard length <= UInt64(end - offset) else { throw ValidationError.malformedWire }
            let input = Reader(bytes: bytes, offset: offset, end: offset + Int(length))
            offset += Int(length)
            return input
        }

        mutating func fixed(count: Int) throws -> UInt64 {
            guard count <= end - offset else { throw ValidationError.malformedWire }
            var value: UInt64 = 0
            for index in 0..<count { value |= UInt64(bytes[offset + index]) << (index * 8) }
            offset += count
            return value
        }

        mutating func skip(_ field: Field) throws {
            switch field.wire {
            case 0: _ = try varint()
            case 1: _ = try fixed(count: 8)
            case 2: _ = try message(field)
            case 5: _ = try fixed(count: 4)
            default: throw ValidationError.malformedWire
            }
        }
    }
}

extension MapboxVectorTileDecoder.Layer: Sendable {}

extension MapboxVectorTileDecoder.Feature: Sendable {}

extension MapboxVectorTileDecoder.Value: Equatable {}

extension MapboxVectorTileDecoder.Value: Sendable {}

extension MapboxVectorTileDecoder.Point: Equatable {}

extension MapboxVectorTileDecoder.Point: Sendable {}

extension MapboxVectorTileDecoder.Geometry: Sendable {}
