@testable import Chio
import Foundation
import Testing

struct MapTileSourceTests {
    @Test("Endpoint templates substitute exactly once in the path and retain immutable metadata")
    func endpoint() throws {
        let source = try OpenMapTilesSource(template: "https://example.test/maps/{z}/{x}/{y}.pbf?format=mvt",
                                           zoomRange: 2...14, metadata: metadata())
        #expect(try source.url(for: .init(zoom: 3, x: 7, y: 1)).absoluteString
                == "https://example.test/maps/3/7/1.pbf?format=mvt")
        #expect(try JSONDecoder().decode(OpenMapTilesSource.self, from: JSONEncoder().encode(source)) == source)
        #expect(throws: MapValidationError.invalidTileSource) { try source.url(for: .init(zoom: 1, x: 0, y: 0)) }
        for template in ["/maps/{z}/{x}/{y}", "ftp://example.test/{z}/{x}/{y}",
                         "https://user:password@example.test/{z}/{x}/{y}",
                         "https://example.test/{z}/{x}/{y}#", "https://example.test/{z}/{x}/{y}#map",
                         "https://{x}.example.test/{z}/{y}", "https://example.test/{z}/{y}?x={x}",
                         "https://example.test/{z}/{x}/{y}/{z}", "https://example.test/{z}/{x}",
                         "https://example.test/{z}/{x}/{y}/{token}",
                         "https://example.test/{z}/{x}/{y}/" + String(repeating: "a", count: 1_024)] {
            #expect(throws: MapValidationError.invalidTileSource) {
                try OpenMapTilesSource(template: template, zoomRange: 2...14, metadata: metadata())
            }
        }
        for range in [-1...14, 2...23] {
            #expect(throws: MapValidationError.invalidTileSource) {
                try OpenMapTilesSource(template: source.template, zoomRange: range, metadata: source.metadata)
            }
        }
        var wire = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any])
        wire["template"] = "https://example.test/{z}/{x}/{y}#invalid"
        #expect(throws: MapValidationError.invalidTileSource) {
            try JSONDecoder().decode(OpenMapTilesSource.self, from: JSONSerialization.data(withJSONObject: wire))
        }
    }

    @Test("Coverage admits every required tile and retains only its declared drawing region")
    func coverage() throws {
        let request = try request()
        let addresses = try MapTilePlan(request: request, zoom: 2).tiles
        let coverage = try MapTileCoverage(tiles: Array(addresses.reversed()), region: request)
        #expect(coverage.tiles == addresses && coverage.zoom == 2 && coverage.region == request)
        #expect(coverage.covers(request))
        #expect(coverage.contains(try .init(latitude: 0, longitude: 179)))
        #expect(coverage.contains(try .init(latitude: 0, longitude: -179)))
        #expect(!coverage.contains(try .init(latitude: 0, longitude: -178.5)))
        #expect(!coverage.contains(try .init(latitude: 0, longitude: 0)))
        #expect(!coverage.contains(try .init(latitude: 90, longitude: 179)))
        #expect(try JSONDecoder().decode(MapTileCoverage.self, from: JSONEncoder().encode(coverage)) == coverage)
        for tiles in [[], [addresses[0], addresses[0]], Array(addresses.dropLast()),
                      [addresses[0], try .init(zoom: 1, x: 0, y: 0)]] {
            #expect(throws: MapValidationError.invalidTileCoverage) { try MapTileCoverage(tiles: tiles, region: request) }
        }
        #expect(throws: MapValidationError.invalidTileCoverage) {
            try MapTileCoverage(tiles: (0..<17).map { try .init(zoom: 5, x: $0, y: 0) }, region: request)
        }
        let regionWire = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request))
        for tiles in [[], [["zoom": 2, "x": 0, "y": 1], ["zoom": 2, "x": 0, "y": 1]],
                      [["zoom": 2, "x": 0, "y": 1]], (0..<17).map { ["zoom": 5, "x": $0, "y": 0] }] {
            let wire = try JSONSerialization.data(withJSONObject: ["tiles": tiles, "region": regionWire])
            #expect(throws: MapValidationError.invalidTileCoverage) {
                try JSONDecoder().decode(MapTileCoverage.self, from: wire)
            }
        }
        let missingRegion = Data(#"{"tiles":[{"zoom":2,"x":0,"y":1}]}"#.utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(MapTileCoverage.self, from: missingRegion) }
        var invalidRegion = try #require(regionWire as? [String: Any])
        invalidRegion["viewport"] = ["columns": 241, "rows": 50, "cellAspectRatio": 2]
        let invalidWire = try JSONSerialization.data(withJSONObject: [
            "tiles": [["zoom": 2, "x": 0, "y": 1]], "region": invalidRegion,
        ])
        #expect(throws: MapValidationError.invalidViewport) {
            try JSONDecoder().decode(MapTileCoverage.self, from: invalidWire)
        }
    }

    @Test("Panning within the same acquired tile cannot claim geometry culled outside the retained region")
    func retainedRegion() throws {
        let region = try request(latitude: 20, longitude: 45, span: 1)
        let tiles = try MapTilePlan(request: region, zoom: 2).tiles
        let expected = try MapTileCoordinate(zoom: 2, x: 2, y: 1)
        #expect(tiles == [expected])
        let coverage = try MapTileCoverage(tiles: tiles, region: region)
        let enclosed = try request(latitude: 20, longitude: 45.1, span: 0.1)
        let movedOutside = try request(latitude: 20, longitude: 45.6, span: 0.1)
        #expect(try MapTilePlan(request: movedOutside, zoom: 2).tiles == tiles)
        #expect(coverage.covers(enclosed))
        #expect(!coverage.covers(movedOutside))
        #expect(coverage.contains(try .init(latitude: 20, longitude: 45.1)))
        #expect(!coverage.contains(try .init(latitude: 20, longitude: 45.6)))
        let tooTall = try request(latitude: 20, longitude: 45, span: 0.8, columns: 100, rows: 100, aspect: 4)
        #expect(!coverage.covers(tooTall))
        let crossing = try request()
        let crossingCoverage = try MapTileCoverage(tiles: MapTilePlan(request: crossing, zoom: 2).tiles, region: crossing)
        #expect(crossingCoverage.covers(try request(longitude: -179.5, span: 0.5)))
        #expect(!crossingCoverage.covers(try request(longitude: -178.5, span: 0.5)))
    }

    @Test("Region bounds clamp Mercator poles and full-world coverage ignores longitude branch changes")
    func worldAndPoles() throws {
        let world = try request(longitude: 170, span: 360, rows: 100)
        let coverage = try MapTileCoverage(tiles: MapTilePlan(request: world, zoom: 2).tiles, region: world)
        #expect(coverage.covers(try request(longitude: -90, span: 360, rows: 100)))
        #expect(coverage.contains(try .init(latitude: MapLimits.mercatorLatitude, longitude: -180)))
        #expect(coverage.contains(try .init(latitude: -MapLimits.mercatorLatitude, longitude: 180)))
        #expect(!coverage.contains(try .init(latitude: 90, longitude: 0)))
        let polar = try request(latitude: MapLimits.mercatorLatitude, longitude: 45, span: 1)
        let polarCoverage = try MapTileCoverage(tiles: MapTilePlan(request: polar, zoom: 2).tiles, region: polar)
        let within = try request(latitude: MapViewport.latitude(mercatorY: 179.8), longitude: 45, span: 0.1)
        let beyond = try request(latitude: MapViewport.latitude(mercatorY: 179), longitude: 45, span: 0.1)
        #expect(polarCoverage.covers(within))
        #expect(!polarCoverage.covers(beyond))
        #expect(polarCoverage.contains(try .init(latitude: MapLimits.mercatorLatitude, longitude: 45)))
        // A partial-world interval must not claim another 360-degree request.
        #expect(!polarCoverage.covers(world))
    }

    @Test("Snapshots require complete tiled coverage and an honest requested source zoom")
    func snapshot() throws {
        let request = try request()
        let addresses = try MapTilePlan(request: request, zoom: 2).tiles
        let source = try source(coverage: .tiled(.init(tiles: addresses, region: request)))
        let snapshot = try MapTileSnapshot(request: request, source: source, requestedZoom: 4)
        #expect(snapshot.attainedZoom == 2 && snapshot.requestedZoom == 4)
        #expect(try JSONDecoder().decode(MapTileSnapshot.self, from: JSONEncoder().encode(snapshot)) == snapshot)
        for zoom in [-1, 1, 23] {
            #expect(throws: MapValidationError.invalidTileSnapshot) {
                try MapTileSnapshot(request: request, source: source, requestedZoom: zoom)
            }
        }
        let narrower = MapTileRequest(camera: try request.camera.zoomed(by: 2), viewport: request.viewport)
        for invalidSource in [try self.source(coverage: .worldwide),
                              try self.source(coverage: .tiled(.init(tiles: addresses, region: narrower)))] {
            #expect(throws: MapValidationError.invalidTileSnapshot) {
                try MapTileSnapshot(request: request, source: invalidSource, requestedZoom: 4)
            }
        }
        var wire = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        wire["requestedZoom"] = 1
        #expect(throws: MapValidationError.invalidTileSnapshot) {
            try JSONDecoder().decode(MapTileSnapshot.self, from: JSONSerialization.data(withJSONObject: wire))
        }
        wire["requestedZoom"] = 4
        wire["source"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(self.source(coverage: .worldwide)))
        #expect(throws: MapValidationError.invalidTileSnapshot) {
            try JSONDecoder().decode(MapTileSnapshot.self, from: JSONSerialization.data(withJSONObject: wire))
        }
    }

    @Test("Adding tile coverage preserves the existing worldwide and bounded offline wire forms")
    func historicalCoverageWire() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let worldwide = Data(#"{"worldwide":{}}"#.utf8)
        #expect(try JSONDecoder().decode(MapCoverage.self, from: worldwide) == .worldwide)
        #expect(try encoder.encode(MapCoverage.worldwide) == worldwide)
        let bounded = Data(#"{"boundedOfflineExtract":{"_0":{"northeast":{"latitude":20,"longitude":30},"southwest":{"latitude":10,"longitude":20}}}}"#.utf8)
        let coverage = try MapCoverage.boundedOfflineExtract(.init(southwest: .init(latitude: 10, longitude: 20),
                                                                   northeast: .init(latitude: 20, longitude: 30)))
        #expect(try JSONDecoder().decode(MapCoverage.self, from: bounded) == coverage)
        #expect(try encoder.encode(coverage) == bounded)
        let region = try request()
        let tiled = try MapCoverage.tiled(.init(tiles: MapTilePlan(request: region, zoom: 2).tiles, region: region))
        #expect(try JSONDecoder().decode(MapCoverage.self, from: encoder.encode(tiled)) == tiled)
    }

    private func request(latitude: Double = 0, longitude: Double = 179, span: Double = 4,
                         columns: Int = 100, rows: Int = 50, aspect: Double = 2) throws -> MapTileRequest {
        try .init(camera: .init(center: .init(latitude: latitude, longitude: longitude), longitudeSpan: span),
                  viewport: .init(columns: columns, rows: rows, cellAspectRatio: aspect))
    }

    private func source(coverage: MapCoverage) throws -> MapSource {
        try .init(dataset: .init(features: []), metadata: metadata(), coverage: coverage)
    }

    private func metadata() throws -> MapSourceMetadata {
        let url = try #require(URL(string: "https://example.test/maps"))
        return try .init(attribution: "Test provider", license: "Test license", licenseURL: url,
                         sourceURL: url, sourceRevision: "revision")
    }
}
