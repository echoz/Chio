import Chio
import Foundation
import Testing

struct MapPublicValueTests {
    @Test("Public checked geography composes a source and preserves its GeoJSON representation")
    func sourceCompositionAndCoding() throws {
        let southwest = try MapCoordinate(latitude: 1, longitude: 103)
        let northeast = try MapCoordinate(latitude: 2, longitude: 104)
        let bounds = try MapCoverage.Bounds(southwest: southwest, northeast: northeast)
        let coverage = MapCoverage.boundedOfflineExtract(bounds)
        let line = try MapPolyline(coordinates: [southwest, northeast])
        let feature = try MapFeature(id: "road", kind: .primaryRoad, name: "Main", geometry: .polyline(line))
        let dataset = try MapDataset(features: [feature])
        let url = try #require(URL(string: "https://example.com/maps"))
        let metadata = try MapSourceMetadata(attribution: "Example map", license: "Example license",
                                            licenseURL: url, sourceURL: url, sourceRevision: "snapshot-1")
        let source = MapSource(dataset: dataset, metadata: metadata, coverage: coverage)
        #expect(source.dataset.vertexCount == 2)
        #expect(source.coverage.contains(southwest))
        #expect(source.metadata.attribution == "Example map")
        #expect(try JSONDecoder().decode(MapSource.self, from: JSONEncoder().encode(source)) == source)
        let encoded = try JSONEncoder().encode(dataset)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["type"] as? String == "FeatureCollection")
        #expect(try MapDataset.decodeGeoJSON(encoded) == dataset)
        let adapter = NormalizedGeoJSONMapAdapter(metadata: metadata, coverage: coverage)
        #expect(try adapted(adapter, encoded) == source)
        let tile = try MapTileCoordinate(zoom: 1, x: 1, y: 0)
        let tileAdapter = OpenMapTilesAdapter(tile: tile, metadata: metadata)
        #expect(tileAdapter.tile == tile)
        #expect(try tile.coverage.contains(MapCoordinate(latitude: 1, longitude: 1)))
    }

    @Test("Source decoding retains nested checked construction and aggregate uniqueness")
    func checkedSourceDecoding() throws {
        let coordinate = try MapCoordinate(latitude: 0, longitude: 0)
        let path = try MapPolyline(coordinates: [coordinate, MapCoordinate(latitude: 1, longitude: 1)])
        let feature = try MapFeature(id: "same", kind: .road, geometry: .polyline(path))
        let encoded = try JSONEncoder().encode(MapDataset(features: [feature]))
        var dataset = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let features = try #require(dataset["features"] as? [[String: Any]])
        dataset["features"] = features + features
        let duplicate = try JSONSerialization.data(withJSONObject: dataset)
        #expect(throws: MapValidationError.duplicateIdentity) {
            try JSONDecoder().decode(MapDataset.self, from: duplicate)
        }
        #expect(throws: MapValidationError.invalidCoordinate) {
            try JSONDecoder().decode(MapCoordinate.self, from: Data(#"{"latitude":91,"longitude":0}"#.utf8))
        }
        #expect(throws: MapValidationError.invalidCamera) {
            try JSONDecoder().decode(MapCamera.self, from: Data(#"{"center":{"latitude":90,"longitude":0},"longitudeSpan":20}"#.utf8))
        }
    }

    @Test("Public camera operations return checked replacements and retain source values")
    func cameraOperations() throws {
        let center = try MapCoordinate(latitude: 0, longitude: 170)
        let camera = try MapCamera(center: center, longitudeSpan: 40)
        let panned = try camera.panned(longitudeFraction: 0.5, latitudeFraction: 0)
        #expect(panned.center.longitude == -170)
        #expect(try camera.zoomed(by: 2).longitudeSpan == 20)
        #expect(camera.center == center)
        #expect(camera.longitudeSpan == 40)
        #expect(MapDetail.minimal.more == .abstract)
        #expect(MapDetail.source.next == .silhouette)
        #expect(throws: MapValidationError.invalidCamera) { try camera.zoomed(by: 0) }
    }

    @Test("Coordinate codecs stop at 20,000 elements before decoding a malformed extra element")
    func incrementalCoordinateLimits() throws {
        let coordinate = #"{"latitude":0,"longitude":0}"#
        let coordinates = Array(repeating: coordinate, count: 20_000).joined(separator: ",")
        let overflow = Data("{\"coordinates\":[\(coordinates),{}]}".utf8)
        #expect(throws: MapValidationError.budgetExceeded) {
            try JSONDecoder().decode(MapPolyline.self, from: overflow)
        }
        #expect(throws: MapValidationError.budgetExceeded) {
            try JSONDecoder().decode(MapRing.self, from: overflow)
        }
        // Before the limit, malformed coordinates retain their actual failure.
        let malformed = Data(#"{"coordinates":[{"latitude":0,"longitude":0},{}]}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(MapPolyline.self, from: malformed) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(MapRing.self, from: malformed) }
    }

    @Test("Polygon coding accepts its ring-count boundary and stops before the malformed 257th ring")
    func incrementalRingCountLimit() throws {
        let ring = try smallRing()
        let boundary = try MapPolygon(rings: Array(repeating: ring, count: 256))
        #expect(try JSONDecoder().decode(MapPolygon.self, from: JSONEncoder().encode(boundary)) == boundary)
        let encodedRing = String(decoding: try JSONEncoder().encode(ring), as: UTF8.self)
        let rings = Array(repeating: encodedRing, count: 256).joined(separator: ",")
        let overflow = Data("{\"rings\":[\(rings),{}]}".utf8)
        #expect(throws: MapValidationError.budgetExceeded) {
            try JSONDecoder().decode(MapPolygon.self, from: overflow)
        }

    }

    @Test("Polygon decoding enforces aggregate vertices and does not decode beyond an exhausted budget")
    func incrementalPolygonVertexLimit() throws {
        let a = try MapCoordinate(latitude: 0, longitude: 0)
        let b = try MapCoordinate(latitude: 0, longitude: 1)
        let c = try MapCoordinate(latitude: 1, longitude: 1)
        let ring = try MapRing(coordinates: [a] + Array(repeating: b, count: 19_997) + [c, a])
        let boundary = try MapPolygon(rings: [ring])
        #expect(boundary.vertexCount == 20_000)
        #expect(try JSONDecoder().decode(MapPolygon.self, from: JSONEncoder().encode(boundary)) == boundary)
        let encodedRing = String(decoding: try JSONEncoder().encode(ring), as: UTF8.self)
        let exhausted = Data("{\"rings\":[\(encodedRing),{}]}".utf8)
        #expect(throws: MapValidationError.budgetExceeded) {
            try JSONDecoder().decode(MapPolygon.self, from: exhausted)
        }
        let extra = String(decoding: try JSONEncoder().encode(smallRing()), as: UTF8.self)
        let overflow = Data("{\"rings\":[\(encodedRing),\(extra)]}".utf8)
        #expect(throws: MapValidationError.budgetExceeded) {
            try JSONDecoder().decode(MapPolygon.self, from: overflow)
        }
        // The shared polygon allowance also stops inside a later ring, before
        // that ring's own independent 20,000-coordinate ceiling is reached.
        let prefix = String(decoding: try JSONEncoder().encode(smallRing()), as: UTF8.self)
        let coordinate = #"{"latitude":0,"longitude":0}"#
        let remaining = Array(repeating: coordinate, count: 19_996).joined(separator: ",")
        let laterRing = "{\"coordinates\":[\(remaining),{}]}"
        let aggregate = Data("{\"rings\":[\(prefix),\(laterRing)]}".utf8)
        #expect(throws: MapValidationError.budgetExceeded) {
            try JSONDecoder().decode(MapPolygon.self, from: aggregate)
        }
    }

    private func smallRing() throws -> MapRing {
        try MapRing(coordinates: [MapCoordinate(latitude: 0, longitude: 0),
                                  MapCoordinate(latitude: 0, longitude: 1),
                                  MapCoordinate(latitude: 1, longitude: 1),
                                  MapCoordinate(latitude: 0, longitude: 0)])
    }

    private func adapted<Adapter: MapSourceAdapter>(_ adapter: Adapter, _ input: Adapter.Input) throws -> MapSource {
        try adapter.adapt(input)
    }
}
