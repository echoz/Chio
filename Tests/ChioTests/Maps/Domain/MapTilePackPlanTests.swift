@testable import Chio
import Foundation
import Testing

struct MapTilePackPlanTests {
    @Test("Exact XYZ edges reuse half-open projection boundaries at every zoom")
    func exactEdges() throws {
        let coordinate = try MapTileCoordinate(zoom: 2, x: 2, y: 1)
        guard case .boundedOfflineExtract(let bounds) = try coordinate.coverage else {
            Issue.record("Expected a tile footprint"); return
        }
        let plan = try MapTilePackPlan(bounds: bounds, zoomRange: 2...3)
        #expect(plan.tiles == [coordinate,
            try MapTileCoordinate(zoom: 3, x: 4, y: 2), try MapTileCoordinate(zoom: 3, x: 4, y: 3),
            try MapTileCoordinate(zoom: 3, x: 5, y: 2), try MapTileCoordinate(zoom: 3, x: 5, y: 3)])
        #expect(plan.maximumBytes == 128 * 1_024 * 1_024)
    }

    @Test("World, poles and seams remain nonwrapping with bounded exact counts")
    func worldAndPoles() throws {
        let world = try bounds(south: -90, west: -180, north: 90, east: 180)
        #expect(try MapTilePackPlan(bounds: world, zoomRange: 1...4).tiles.count == 340)
        let limit = try MapTilePackPlan(bounds: world, zoomRange: 5...5)
        #expect(limit.tiles.count == 1_024)
        #expect(Set(limit.tiles).count == 1_024)
        #expect(throws: MapTilePackPlan.ValidationError.tileLimitExceeded) {
            try MapTilePackPlan(bounds: world, zoomRange: 1...5)
        }
        #expect(throws: MapTilePackPlan.ValidationError.tileLimitExceeded) {
            try MapTilePackPlan(bounds: world, zoomRange: 22...22)
        }
        let north = try MapTilePackPlan(bounds: bounds(south: 86, west: 0, north: 90, east: 90), zoomRange: 2...2)
        #expect(north.tiles == [try MapTileCoordinate(zoom: 2, x: 2, y: 0)])
        let south = try MapTilePackPlan(bounds: bounds(south: -90, west: -180, north: -86, east: -90), zoomRange: 2...2)
        #expect(south.tiles == [try MapTileCoordinate(zoom: 2, x: 0, y: 3)])
        #expect(throws: MapCoverage.ValidationError.invalidBounds) {
            try bounds(south: -1, west: 170, north: 1, east: -170)
        }
    }

    @Test("Construction and decoding enforce zoom, byte and enumeration budgets")
    func validationAndCoding() throws {
        let region = try bounds(south: 1, west: 1, north: 2, east: 2)
        for range in [0...1, 1...23, 1...Int.max] {
            #expect(throws: MapTilePackPlan.ValidationError.invalidConfiguration) {
                try MapTilePackPlan(bounds: region, zoomRange: range)
            }
        }
        for budget in [Int.min, 0, 256 * 1_024 * 1_024 + 1, Int.max] {
            #expect(throws: MapTilePackPlan.ValidationError.invalidConfiguration) {
                try MapTilePackPlan(bounds: region, zoomRange: 1...1, maximumBytes: budget)
            }
        }
        let plan = try MapTilePackPlan(bounds: region, zoomRange: 1...2, maximumBytes: 1)
        let encoded = try JSONEncoder().encode(plan)
        #expect(try JSONDecoder().decode(MapTilePackPlan.self, from: encoded) == plan)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["tiles"] == nil)
        object["maximumBytes"] = 0
        let invalid = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: MapTilePackPlan.ValidationError.invalidConfiguration) {
            try JSONDecoder().decode(MapTilePackPlan.self, from: invalid)
        }
        object["maximumBytes"] = 1
        object["bounds"] = ["southwest": ["latitude": 2, "longitude": 2],
                            "northeast": ["latitude": 1, "longitude": 1]]
        #expect(throws: MapCoverage.ValidationError.invalidBounds) {
            try JSONDecoder().decode(MapTilePackPlan.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }

    private func bounds(south: Double, west: Double, north: Double, east: Double) throws -> MapCoverage.Bounds {
        try MapCoverage.Bounds(southwest: MapCoordinate(latitude: south, longitude: west),
                               northeast: MapCoordinate(latitude: north, longitude: east))
    }
}
