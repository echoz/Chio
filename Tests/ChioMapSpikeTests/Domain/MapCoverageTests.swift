@testable import ChioMapSpike
import Foundation
import Testing

struct MapCoverageTests {
    @Test("Coverage includes query edges and distinguishes worldwide from a bounded offline extract")
    func availability() throws {
        let southwest = try MapCoordinate(latitude: 1.278, longitude: 103.842)
        let northeast = try MapCoordinate(latitude: 1.300, longitude: 103.870)
        let coverage = try MapCoverage.boundedOfflineExtract(.init(southwest: southwest, northeast: northeast))
        #expect(coverage.contains(southwest) && coverage.contains(northeast))
        #expect(coverage.contains(try MapCoordinate(latitude: 1.289, longitude: 103.856)))
        for coordinate in [
            try MapCoordinate(latitude: 1.277, longitude: 103.856),
            try MapCoordinate(latitude: 1.301, longitude: 103.856),
            try MapCoordinate(latitude: 1.289, longitude: 103.841),
            try MapCoordinate(latitude: 1.289, longitude: 103.871),
        ] {
            #expect(!coverage.contains(coordinate))
            #expect(MapCoverage.worldwide.contains(coordinate))
        }
        #expect(MapCoverage.worldwide.contains(try MapCoordinate(latitude: 90, longitude: -180)))
        for value in [MapCoverage.worldwide, coverage] {
            #expect(try JSONDecoder().decode(MapCoverage.self, from: JSONEncoder().encode(value)) == value)
        }
    }

    @Test("Bounds reject empty, reversed and wrapping boxes through construction and decoding")
    func checkedBounds() throws {
        let zero = try MapCoordinate(latitude: 0, longitude: 0)
        for northeast in [
            try MapCoordinate(latitude: 0, longitude: 1),
            try MapCoordinate(latitude: 1, longitude: 0),
            try MapCoordinate(latitude: -1, longitude: 1),
            try MapCoordinate(latitude: 1, longitude: -1),
        ] {
            #expect(throws: MapCoverage.ValidationError.invalidBounds) {
                try MapCoverage.Bounds(southwest: zero, northeast: northeast)
            }
            let input = #"{"southwest":{"latitude":0,"longitude":0},"northeast":{"latitude":\#(northeast.latitude),"longitude":\#(northeast.longitude)}}"#
            #expect(throws: MapCoverage.ValidationError.invalidBounds) {
                try JSONDecoder().decode(MapCoverage.Bounds.self, from: Data(input.utf8))
            }
            let coverage = #"{"boundedOfflineExtract":{"_0":\#(input)}}"#
            #expect(throws: MapCoverage.ValidationError.invalidBounds) {
                try JSONDecoder().decode(MapCoverage.self, from: Data(coverage.utf8))
            }
        }
        #expect(throws: MapValidationError.invalidCoordinate) {
            try JSONDecoder().decode(MapCoverage.Bounds.self, from: Data(
                #"{"southwest":{"latitude":-91,"longitude":0},"northeast":{"latitude":1,"longitude":1}}"#.utf8))
        }
    }
}
