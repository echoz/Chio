@testable import ChioMaps
@testable import Chio
import Foundation
import Testing

struct MapGeoJSONTests {
    @Test("FeatureCollection codec preserves longitude/latitude ordering, identity, kind and holes")
    func fixtureContract() throws {
        let dataset = try MapDataset.decodeGeoJSON(Data(valid.utf8))
        #expect(dataset.features.map(\.id) == ["road-1", "water-1"])
        #expect(dataset.features[0].kind == .primaryRoad)
        #expect(dataset.features[0].name == "Road")
        guard case .polyline(let road) = dataset.features[0].geometry,
              case .polygon(let water) = dataset.features[1].geometry else { Issue.record("Wrong geometry"); return }
        #expect(road.coordinates[0].latitude == 1 && road.coordinates[0].longitude == 103)
        #expect(water.rings.count == 2)
        let encoded = try JSONEncoder().encode(dataset)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["type"] as? String == "FeatureCollection")
        #expect(try MapDataset.decodeGeoJSON(encoded) == dataset)
    }

    @Test("Decoder rejects unsupported geometries, malformed pairs, missing IDs and invalid rings")
    func malformedInput() {
        for input in [
            valid.replacingOccurrences(of: "LineString", with: "MultiLineString"),
            valid.replacingOccurrences(of: "[103,1]", with: "[103,1,4]"),
            valid.replacingOccurrences(of: "[103,1]", with: "[181,1]"),
            valid.replacingOccurrences(of: #""id":"road-1","# , with: ""),
            valid.replacingOccurrences(of: #""id":"road-1""#, with: #""id":1""#),
            valid.replacingOccurrences(of: "primaryRoad", with: "unknown"),
            valid.replacingOccurrences(of: "[0,0],[4,0],[4,4],[0,4],[0,0]", with: "[0,0],[4,0],[4,4],[0,4]"),
        ] {
            #expect(throws: (any Error).self) { try MapDataset.decodeGeoJSON(Data(input.utf8)) }
        }
    }

    @Test("Dataset bounds feature count, vertices, input bytes and stable unique identity")
    func budgetsAndIdentity() throws {
        let feature = try MapDataset.decodeGeoJSON(Data(valid.utf8)).features[0]
        #expect(throws: MapValidationError.duplicateIdentity) { try MapDataset(features: [feature, feature]) }
        #expect(throws: MapValidationError.budgetExceeded) {
            try MapDataset(features: Array(repeating: feature, count: MapLimits.features + 1))
        }
        #expect(throws: MapValidationError.budgetExceeded) {
            try MapDataset.decodeGeoJSON(Data(repeating: 32, count: MapLimits.geoJSONBytes + 1))
        }
        let tooManyPoints = Array(repeating: "[0,0]", count: MapLimits.pathVertices + 1).joined(separator: ",")
        let input = #"{"type":"FeatureCollection","features":[{"type":"Feature","id":"x","properties":{"kind":"road"},"geometry":{"type":"LineString","coordinates":["# + tooManyPoints + "]}}]}"
        #expect(throws: MapValidationError.budgetExceeded) { try MapDataset.decodeGeoJSON(Data(input.utf8)) }
        let empty = try MapDataset.decodeGeoJSON(Data(#"{"type":"FeatureCollection","features":[]}"#.utf8))
        #expect(empty.features.isEmpty && empty.vertexCount == 0)
    }

    private let valid = #"{"type":"FeatureCollection","features":[{"type":"Feature","id":"road-1","properties":{"kind":"primaryRoad","name":"Road"},"geometry":{"type":"LineString","coordinates":[[103,1],[104,2]]}},{"type":"Feature","id":"water-1","properties":{"kind":"water","name":"Lake"},"geometry":{"type":"Polygon","coordinates":[[[0,0],[4,0],[4,4],[0,4],[0,0]],[[1,1],[1,2],[2,2],[2,1],[1,1]]]}}]}"#
}
