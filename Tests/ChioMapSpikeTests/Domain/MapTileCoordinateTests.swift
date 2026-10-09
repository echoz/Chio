@testable import ChioMapSpike
import Foundation
import Testing

struct MapTileCoordinateTests {
    @Test("XYZ construction and decoding retain checked bounds")
    func addressValidation() throws {
        for address in [(-1,0,0), (23,0,0), (2,-1,0), (2,4,0), (2,0,4)] {
            #expect(throws: MapTileCoordinate.ValidationError.invalidAddress) {
                try MapTileCoordinate(zoom: address.0, x: address.1, y: address.2)
            }
        }
        for input in [#"{"zoom":23,"x":0,"y":0}"#, #"{"zoom":2,"x":4,"y":0}"#] {
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(MapTileCoordinate.self, from: Data(input.utf8))
            }
        }
        let tile = try MapTileCoordinate(zoom: 14, x: 12918, y: 8133)
        #expect(try JSONDecoder().decode(MapTileCoordinate.self, from: JSONEncoder().encode(tile)) == tile)
    }

    @Test("XYZ coordinates respect Y-down orientation, extent, buffers and geographic coverage")
    func coordinateConversion() throws {
        let tile = try MapTileCoordinate(zoom: 1, x: 1, y: 0)
        let northwest = try tile.coordinate(x: 0, y: 0, extent: 4096)
        let southeast = try tile.coordinate(x: 4096, y: 4096, extent: 4096)
        #expect(northwest.longitude == 0)
        #expect(abs(northwest.latitude - MapLimits.mercatorLatitude) < 0.000_000_001)
        #expect(southeast.longitude == 180 && southeast.latitude == 0)
        #expect(try tile.coordinate(x: 2048, y: 2048, extent: 4096)
                == tile.coordinate(x: 128, y: 128, extent: 256))
        let buffer = try tile.coordinate(x: -16, y: 2048, extent: 4096)
        let coverage = try tile.coverage
        #expect(buffer.longitude < 0 && !coverage.contains(buffer))
        #expect(try tile.coordinate(x: 4112, y: 2048, extent: 4096).longitude < -179)
        #expect(throws: (any Error).self) { try tile.coordinate(x: 0, y: 0, extent: 0) }
    }
}
