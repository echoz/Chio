@testable import ChioMaps
@testable import Chio
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

    @Test("Park point labels are excluded while park polygons retain strict geometry validation")
    func parkLabels() throws {
        let adapter = OpenMapTilesAdapter(tile: try .init(zoom: 12, x: 3229, y: 2033), metadata: try credit())
        // Exact geometry words from the retained Central Catchment Nature Reserve label.
        let point = integer(3, 1) + message(4, [UInt32(9),590,5441].flatMap { varint(UInt64($0)) })
        let polygon = integer(3, 3) + message(4, [UInt32(9),0,0,18,2,0,0,2,15].flatMap { varint(UInt64($0)) })
        let mixed = message(3, integer(15, 2) + message(1, Array("park".utf8)) + integer(5, 4096)
                            + message(2, point) + message(2, polygon))
        let source = try adapter.adapt(Data(mixed))
        #expect(source.dataset.features.count == 1)
        #expect(source.dataset.features.first?.kind == .park)
        #expect(source.dataset.features.first?.id == "mvt/12/3229/2033/park/1/absent/0")
        #expect(throws: OpenMapTilesAdapter.ValidationError.invalidGeometry) {
            try adapter.adapt(Data(layer("park", type: 2, words: [9,0,0,10,2,2])))
        }
        #expect(throws: OpenMapTilesAdapter.ValidationError.invalidTags) {
            let invalidPointTags = point + message(2, [0,0]) // No key/value tables.
            _ = try adapter.adapt(Data(message(3, integer(15, 2) + message(1, Array("park".utf8))
                + integer(5, 4096) + message(2, invalidPointTags))))
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

    @Test("Acquisition admits whole visible parts after validating over 4000 offscreen parts")
    func regionalAdmissionBudget() throws {
        let tile = try MapTileCoordinate(zoom: 14, x: 12919, y: 8133)
        let adapter = OpenMapTilesAdapter(tile: tile, metadata: try credit())
        let request = try centeredRequest(tile: tile)
        let outside: [UInt32] = [9,0,0,10,2,2] // (0,0) to (1,1), far outside the requested centre.
        let visible: [UInt32] = [9,3800,4096,10,600,0] // (1900,2048) to (2200,2048).
        let input = Data(layer("transportation", type: 2,
                               featureWords: Array(repeating: outside, count: 4_001) + [visible], sourceClass: "primary"))
        #expect(throws: MapValidationError.budgetExceeded) { try adapter.adapt(input) }
        let selected = try adapter.adapt(input, intersecting: request)
        #expect(selected.features.count == 1 && selected.vertexCount == 2)
        #expect(selected.features.first?.id == "mvt/14/12919/8133/transportation/4001/1/0")
        guard case .polyline(let retained) = try #require(selected.features.first).geometry else {
            Issue.record("Expected the whole visible road"); return
        }
        let coordinates = try [tile.coordinate(x: 1900, y: 2048, extent: 4096),
                               tile.coordinate(x: 2200, y: 2048, extent: 4096)]
        #expect(retained.coordinates == coordinates)
        let visibleOver = Data(layer("transportation", type: 2, words: visible,
                                     sourceClass: "primary", featureCopies: 4_001))
        #expect(throws: MapValidationError.budgetExceeded) { try adapter.adapt(visibleOver, intersecting: request) }
    }

    @Test("Selected offscreen geometry and feature names still validate before spatial admission")
    func invalidOffscreenCandidate() throws {
        let tile = try MapTileCoordinate(zoom: 14, x: 12919, y: 8133)
        let adapter = OpenMapTilesAdapter(tile: tile, metadata: try credit())
        let request = try centeredRequest(tile: tile)
        let visible: [UInt32] = [9,3800,4096,10,600,0]
        for malformed in [[UInt32(9),0,0], [9,0,0,10,0,0]] {
            let input = Data(layer("transportation", type: 2, featureWords: [visible, malformed], sourceClass: "primary"))
            #expect(throws: OpenMapTilesAdapter.ValidationError.invalidGeometry) {
                try adapter.adapt(input, intersecting: request)
            }
        }
        for invalidName in ["Bad\nname", String(repeating: "a", count: 257)] {
            let input = Data(layer("transportation", type: 2, featureWords: [visible, [9,0,0,10,2,2]],
                                   sourceClass: "primary", names: ["Visible", invalidName]))
            #expect(throws: MapValidationError.invalidIdentity) { try adapter.adapt(input, intersecting: request) }
        }
        // A valid offscreen line in an area layer must still reject its schema mismatch.
        let wrongType = Data(layer("water", type: 2, words: [9,0,0,10,2,2]))
        #expect(throws: OpenMapTilesAdapter.ValidationError.invalidGeometry) {
            try adapter.adapt(wrongType, intersecting: request)
        }
    }

    @Test("Spatial admission retains a crossing road and an enclosing polygon with all original holes")
    func crossingAndEnclosingGeometry() throws {
        let tile = try MapTileCoordinate(zoom: 14, x: 12919, y: 8133)
        let adapter = OpenMapTilesAdapter(tile: tile, metadata: try credit())
        let request = try centeredRequest(tile: tile)
        // Endpoints (1000,2048)/(3000,2048) both lie outside the centre viewport.
        let crossing: [UInt32] = [9,2000,4096,10,4000,0]
        // Exterior (1000,1000)..(3000,3000) encloses the viewport with no vertex in it.
        // Interior (1800,1800)..(2200,2200) is a counterclockwise hole.
        let enclosing: [UInt32] = [9,2000,2000,26,4000,0,0,4000,3999,0,15,
                                   9,1600,2399,26,0,800,800,0,0,799,15]
        let input = Data(layer("transportation", type: 2, words: crossing, sourceClass: "primary")
                         + layer("water", type: 3, words: enclosing))
        let whole = try adapter.adapt(input).dataset
        let selected = try adapter.adapt(input, intersecting: request)
        #expect(selected == whole && selected.features.count == 2 && selected.vertexCount == 12)
        guard case .polygon(let polygon) = try #require(selected.features.last).geometry,
              case .polyline(let road) = try #require(selected.features.first).geometry else {
            Issue.record("Expected complete water and road geometry"); return
        }
        #expect(polygon.rings.count == 2 && polygon.rings.allSatisfy { $0.coordinates.count == 5 })
        #expect(!road.coordinates.contains { request.contains($0) })
        #expect(!polygon.rings[0].coordinates.contains { request.contains($0) })
        #expect(try MapPreparation.mayIntersect(.polyline(road), request: request))
        #expect(try MapPreparation.mayIntersect(.polygon(polygon), request: request))
    }

    @Test("Culling one multipart path preserves the surviving original part identity")
    func multipartAdmissionIdentity() throws {
        let tile = try MapTileCoordinate(zoom: 14, x: 12919, y: 8133)
        let adapter = OpenMapTilesAdapter(tile: tile, metadata: try credit())
        let request = try centeredRequest(tile: tile)
        // The second MoveTo is relative to the first path's last LineTo (1,1).
        let words: [UInt32] = [9,0,0,10,2,2,9,3798,4094,10,600,0]
        let input = Data(layer("transportation", type: 2, words: words, sourceClass: "primary"))
        let whole = try adapter.adapt(input).dataset
        let selected = try adapter.adapt(input, intersecting: request)
        #expect(selected.features == Array(whole.features.dropFirst()))
        #expect(selected.features.first?.id == "mvt/14/12919/8133/transportation/0/1/1")
        #expect(try !MapPreparation.mayIntersect(whole.features[0].geometry, request: request))
    }

    @Test("Spatial admission uses the renderer's longitude branch across the dateline")
    func datelineAdmission() throws {
        let line = try MapGeometry.polyline(.init(coordinates: [.init(latitude: 0, longitude: 178),
                                                               .init(latitude: 0, longitude: -178)]))
        let viewport = try MapViewport(columns: 100, rows: 50)
        let seam = try MapTileRequest(camera: .init(center: .init(latitude: 0, longitude: 179), longitudeSpan: 4),
                                      viewport: viewport)
        let distant = try MapTileRequest(camera: .init(center: .init(latitude: 0, longitude: 0), longitudeSpan: 4),
                                         viewport: viewport)
        #expect(try MapPreparation.mayIntersect(line, request: seam))
        #expect(try !MapPreparation.mayIntersect(line, request: distant))
    }

    @Test("Half-world tile edges subdivide exactly in both directions without rounding projected vertices")
    func longEdges() throws {
        let tile = try MapTileCoordinate(zoom: 1, x: 0, y: 0)
        let adapter = OpenMapTilesAdapter(tile: tile, metadata: try credit())
        let path: [(Int64, Int64)] = [(0, 2000), (4160, 2001)]
        for points in [path, Array(path.reversed())] {
            let data = Data(layer("transportation", type: 2, words: geometryWords(paths: [points]), sourceClass: "primary"))
            let source = try adapter.adapt(data)
            guard case .polyline(let line) = source.dataset.features[0].geometry else {
                Issue.record("Expected a road"); return
            }
            #expect(line.coordinates.count == 3)
            #expect(line.coordinates.first == (try tile.coordinate(x: points[0].0, y: points[0].1, extent: 4096)))
            #expect(line.coordinates.last == (try tile.coordinate(x: points[1].0, y: points[1].1, extent: 4096)))
            // Independent inverse Web Mercator for the exact fractional midpoint.
            #expect(line.coordinates[1].longitude == -88.59375)
            let latitude = atan(sinh(Double.pi * (1 - 2 * (2000.5 / 4096 / 2)))) * 180 / Double.pi
            #expect(line.coordinates[1].latitude == latitude)
        }
        let halfWorld = OpenMapTilesAdapter(tile: try MapTileCoordinate(zoom: 0, x: 0, y: 0), metadata: try credit())
        let half = Data(layer("transportation", type: 2, words: geometryWords(paths: [[(0, 2048), (2048, 2048)]]), sourceClass: "primary"))
        guard case .polyline(let line) = try halfWorld.adapt(half).dataset.features[0].geometry else {
            Issue.record("Expected a half-world road"); return
        }
        #expect(line.coordinates.map(\.longitude) == [-180, -90, 0])
        let short = Data(layer("transportation", type: 2, words: geometryWords(paths: [[(0, 2048), (1024, 2048)]]), sourceClass: "primary"))
        #expect(try halfWorld.adapt(short).dataset.vertexCount == 2)
    }

    @Test("Coarse polygon normalization retains holes and rejects ambiguous world spans and hole branches")
    func coarsePolygons() throws {
        let tile = try MapTileCoordinate(zoom: 1, x: 0, y: 0)
        let adapter = OpenMapTilesAdapter(tile: tile, metadata: try credit())
        let exterior: [(Int64, Int64)] = [(0, 1000), (4160, 1000), (4160, 3000), (0, 3000)]
        let hole: [(Int64, Int64)] = [(100, 1500), (100, 2500), (200, 2500), (200, 1500)]
        let data = Data(layer("water", type: 3, words: geometryWords(paths: [exterior, hole], isPolygon: true)))
        guard case .polygon(let polygon) = try adapter.adapt(data).dataset.features[0].geometry else {
            Issue.record("Expected coarse water"); return
        }
        #expect(polygon.rings.map { $0.coordinates.count } == [7, 5])
        #expect(polygon.rings[1].coordinates == (try (hole + [hole[0]]).map { try tile.coordinate(x: $0.0, y: $0.1, extent: 4096) }))
        // This buffered whole-world shape represents the actual z0 ocean's
        // ambiguous branch class; preserving its ring parity needs decomposition.
        let world = OpenMapTilesAdapter(tile: try MapTileCoordinate(zoom: 0, x: 0, y: 0), metadata: try credit())
        let buffered: [(Int64, Int64)] = [(-64, -64), (4160, -64), (4160, 4160), (-64, 4160)]
        #expect(throws: OpenMapTilesAdapter.ValidationError.invalidGeometry) {
            try world.adapt(Data(layer("water", type: 3, words: geometryWords(paths: [buffered], isPolygon: true))))
        }
        #expect(throws: OpenMapTilesAdapter.ValidationError.invalidGeometry) {
            try world.adapt(Data(layer("transportation", type: 2,
                                      words: geometryWords(paths: [[(0, 2048), (4096, 2048)]]), sourceClass: "primary")))
        }
        // Exterior midpoint 100 and hole midpoint 4196 differ by exactly half
        // the z1 world. A nearest-copy choice would have no unique source branch.
        let local: [(Int64, Int64)] = [(0, 1000), (200, 1000), (200, 3000), (0, 3000)]
        let ambiguous: [(Int64, Int64)] = [(4146, 1500), (4146, 2500), (4246, 2500), (4246, 1500)]
        #expect(throws: OpenMapTilesAdapter.ValidationError.invalidGeometry) {
            try adapter.adapt(Data(layer("water", type: 3, words: geometryWords(paths: [local, ambiguous], isPolygon: true))))
        }
    }

    @Test("Inserted vertices obey path, polygon and multipart record budgets before publication")
    func normalizationBudgets() throws {
        let adapter = OpenMapTilesAdapter(tile: try MapTileCoordinate(zoom: 1, x: 0, y: 0), metadata: try credit())
        func path(prefixCount: Int) -> [(Int64, Int64)] {
            (0..<prefixCount).map { (Int64($0 % 2), Int64($0)) } + [(4160, 20000)]
        }
        let exact = path(prefixCount: 19998) // 19999 raw + one inserted vertex.
        let accepted = Data(layer("transportation", type: 2, words: geometryWords(paths: [exact]), sourceClass: "primary"))
        #expect(try adapter.adapt(accepted).dataset.vertexCount == 20000)
        let over = Data(layer("transportation", type: 2, words: geometryWords(paths: [path(prefixCount: 19999)]), sourceClass: "primary"))
        #expect(throws: OpenMapTilesAdapter.ValidationError.budgetExceeded) { try adapter.adapt(over) }
        let record = Array(repeating: exact, count: 10)
        #expect(try adapter.adapt(Data(layer("transportation", type: 2, words: geometryWords(paths: record), sourceClass: "primary"))).dataset.vertexCount == 200000)
        #expect(throws: OpenMapTilesAdapter.ValidationError.budgetExceeded) {
            try adapter.adapt(Data(layer("transportation", type: 2,
                                        words: geometryWords(paths: record + [[(0, 0), (1, 1)]]), sourceClass: "primary")))
        }
        let exterior: [(Int64, Int64)] = [(0, 0), (4160, 0), (4160, 22000), (0, 22000)]
        func hole(verticalVertices: Int) -> [(Int64, Int64)] {
            [(100, 100)] + (1...verticalVertices).map { (Int64(100), Int64($0 + 100)) }
                + [(200, Int64(verticalVertices + 100)), (200, 100)]
        }
        // Each ring fits on its own. Closure and both inserted exterior
        // midpoints must also fit their shared polygon allowance with the hole.
        let polygon = Data(layer("water", type: 3,
                                 words: geometryWords(paths: [exterior, hole(verticalVertices: 19989)], isPolygon: true)))
        #expect(try adapter.adapt(polygon).dataset.vertexCount == 20000)
        #expect(throws: OpenMapTilesAdapter.ValidationError.budgetExceeded) {
            try adapter.adapt(Data(layer("water", type: 3,
                                        words: geometryWords(paths: [exterior, hole(verticalVertices: 19990)], isPolygon: true))))
        }
    }

    private func geometryWords(paths: [[(Int64, Int64)]], isPolygon: Bool = false) -> [UInt32] {
        var x: Int64 = 0, y: Int64 = 0
        var words: [UInt32] = []
        for path in paths {
            words.append(9)
            for (index, point) in path.enumerated() {
                if index == 1 { words.append(UInt32((path.count - 1) << 3 | 2)) }
                let dx = point.0 - x, dy = point.1 - y
                words.append(UInt32((dx << 1) ^ (dx >> 63)))
                words.append(UInt32((dy << 1) ^ (dy >> 63)))
                x = point.0; y = point.1
            }
            if isPolygon { words.append(15) }
        }
        return words
    }

    private func credit() throws -> MapSourceMetadata {
        let url = try #require(URL(string: "https://example.test/source"))
        return try MapSourceMetadata(attribution: "Test provider", license: "Test license", licenseURL: url,
                                     sourceURL: url, sourceRevision: "snapshot")
    }

    private func centeredRequest(tile: MapTileCoordinate) throws -> MapTileRequest {
        try .init(camera: .init(center: tile.coordinate(x: 2048, y: 2048, extent: 4096),
                                longitudeSpan: 360 / Double(1 << tile.zoom) / 4),
                  viewport: .init(columns: 100, rows: 50))
    }

    private func layer(_ name: String, type: UInt64, featureWords: [[UInt32]],
                       sourceClass: String = "", names: [String] = []) -> [UInt8] {
        var values = [sourceClass]
        var features: [UInt8] = []
        for (ordinal, words) in featureWords.enumerated() {
            let name = names.isEmpty ? "" : names[ordinal]
            let index: Int
            if let existing = values.firstIndex(of: name) { index = existing }
            else { index = values.count; values.append(name) }
            let tags = [UInt64(0),0,1,UInt64(index)].flatMap { varint($0) }
            let feature = integer(1, 1) + integer(3, type) + message(2, tags)
                + message(4, words.flatMap { varint(UInt64($0)) })
            features += message(2, feature)
        }
        let tables = ["class", "name"].flatMap { message(3, Array($0.utf8)) }
            + values.flatMap { message(4, message(1, Array($0.utf8))) }
        return message(3, integer(15, 2) + message(1, Array(name.utf8)) + integer(5, 4096) + tables + features)
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
